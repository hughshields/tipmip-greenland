function results=md2tipmip(md,directoryname,source_id,ism_id,esm_id,variant_id,resolution_km,exp_prefix,experiment_override,include_initial)
	%Create netcdf files for one TIPMIP-ICE SHEETS experiment, for Greenland (GrIS) only.
	%
	%Follows the TIPMIP-ICE SHEETS protocol (which in turn follows ISMIP7 for variable names,
	%grid and state/flux conventions), but differs from ISMIP7 in the following ways:
	%  - one file per variable, written into <directoryname>/<experiment-name>/
	%  - file name: <variable>_<ice-sheet>_<modelling-group>_<ice-sheet-model>_<experiment-name>.nc
	%  - time: days since 0000-1-1, 365_day calendar, continuous across the experiment chain
	%    (md time is taken to be the ESM simulation year, e.g. the Stab2.0 run starting at
	%    t=94 gets state time (94+1)*365 for its first year)
	%  - only the Table 3 gridded variables are written (no scalar time series)
	%  - files are written one year at a time, so memory use is independent of run length
	%
	%md:                   ISSM model with results.TransientSolution
	%directoryname:        parent output directory (must exist); a subdirectory named after
	%                      the experiment is created inside it
	%source_id:            modelling group name, no '_' (optional, default 'Dartmouth')
	%ism_id:               ice-sheet model name, no '_' (optional, default 'ISSM')
	%esm_id:               ESM that provided the forcing (optional, default 'UKESM1-2-LL')
	%variant_id:           'def' (Tier 1, default), 'LowAtm', 'HighAtm', 'LowOcn', 'HighOcn'
	%resolution_km:        output grid resolution, 1/2/4/8/16 (optional, default 1)
	%exp_prefix:           'Exp01'..'Exp08'. Optional: derived from variant_id (def->Exp01,
	%                      LowAtm->Exp02, HighAtm->Exp03, LowOcn->Exp04, HighOcn->Exp05).
	%                      Must be given for Tier 3 (ESM uncertainty) runs, e.g. 'Exp06'.
	%experiment_override:  full experiment name to use instead of the one built here (optional)
	%include_initial:      write the initial state as the first entry of state variables
	%                      (Table 4 of the protocol). Optional; default true for ramp and ctrl,
	%                      false otherwise (stabilization/reversal continue from a previous run).
	%
	%The experiment type is parsed from md.miscellaneous.name, which must follow
	%   Greenland_TIPMIP_<experiment>_Run[_anything]
	%where <experiment> is (case-insensitive) one of
	%   Ramp, Ctrl, Stab2.0, Stab4.0, Stab2.0-200y-RevPI, Stab2.0-1000y-RevPI,
	%   Stab4.0-200y-Rev2.0, Stab4.0-1000y-Rev2.0, Stab4.0-200y-RevPI, Stab4.0-1000y-RevPI
	%e.g. Greenland_TIPMIP_Stab4.0-200y-Rev2.0_Run -> Exp01-UKESM1-2-LL-stab4.0-200y-rev2.0-def

	if nargin<3 || isempty(source_id),           source_id='Dartmouth'; end
	if nargin<4 || isempty(ism_id),              ism_id='ISSM'; end
	if nargin<5 || isempty(esm_id),              esm_id='UKESM1-2-LL'; end
	if nargin<6 || isempty(variant_id),          variant_id='def'; end
	if nargin<7 || isempty(resolution_km),       resolution_km=1; end
	if nargin<8,                                 exp_prefix=''; end
	if nargin<9,                                 experiment_override=''; end
	if nargin<10,                                include_initial=[]; end

	if exist(directoryname)~=7,
		error(['directory ' directoryname ' does not exist']);
	end
	if any(source_id=='_') || any(ism_id=='_'),
		error('source_id and ism_id must not contain ''_'' (it is the file-name field separator)');
	end
	allowed_res=[1 2 4 8 16];
	if ~any(resolution_km==allowed_res),
		error(['resolution_km=' num2str(resolution_km) ' is not allowed (allowed: ' num2str(allowed_res) ')']);
	end
	icesheetname='GrIS';

	%Experiment name, parsed from md.miscellaneous.name {{{
	try
		runname = md.miscellaneous.name;
	catch
		error('md.miscellaneous.name must be set, e.g. Greenland_TIPMIP_Ramp_Run');
	end
	nameparts = strsplit(runname,'_');
	if numel(nameparts)<3,
		error(['md.miscellaneous.name (''' runname ''') does not follow Greenland_TIPMIP_<experiment>_Run']);
	end
	exptoken = lower(nameparts{3});
	if isempty(regexp(exptoken,'^(ramp|ctrl|stab2\.0|stab4\.0|stab2\.0-(200|1000)y-revpi|stab4\.0-(200|1000)y-(rev2\.0|revpi))$','once')),
		error(['Experiment token ''' nameparts{3} ''' (from md.miscellaneous.name) is not a TIPMIP-ICE SHEETS experiment']);
	end

	if isempty(exp_prefix),
		switch lower(variant_id)
			case 'def',     exp_prefix='Exp01';
			case 'lowatm',  exp_prefix='Exp02';
			case 'highatm', exp_prefix='Exp03';
			case 'lowocn',  exp_prefix='Exp04';
			case 'highocn', exp_prefix='Exp05';
			otherwise, error(['Unknown variant_id ''' variant_id ''' - pass exp_prefix explicitly (e.g. ''Exp06'' for Tier 3)']);
		end
	end
	if ~isempty(experiment_override),
		experiment_name = experiment_override;
	elseif strcmp(exptoken,'ctrl'),
		experiment_name = [exp_prefix '-ctrl'];
	else
		experiment_name = [exp_prefix '-' esm_id '-' exptoken '-' variant_id];
	end
	if isempty(include_initial),
		include_initial = any(strcmp(exptoken,{'ramp','ctrl'}));
	end
	fprintf('md2tipmip: experiment %s\n',experiment_name);

	%Each experiment gets its own directory, named after the experiment, below directoryname
	outdir = fullfile(directoryname,experiment_name);
	if exist(outdir)~=7,
		mkdir(outdir);
	end
	mkfname = @(variable_id) fullfile(outdir,[variable_id '_' icesheetname '_' source_id '_' ism_id '_' experiment_name '.nc']);
	%}}}

	%Group solutions into model years {{{
	%A solution saved at time t belongs to year floor-style index ceil(t)-1, so that the
	%end-of-year snapshot (t = 39.0) belongs to year 38 (covering [38,39)), not to year 39.
	%Time is rounded to 1e-3 yr first to absorb float drift in the saved times.
	sol     = md.results.TransientSolution;
	Nsol    = numel(sol);
	tr      = round(arrayfun(@(k) sol(k).time,1:Nsol)*1000)/1000;
	t0      = round(md.timestepping.start_time*1000)/1000;
	if abs(t0-round(t0))>1e-3,
		error(['md.timestepping.start_time=' num2str(t0) ' is not an integer year - year registration would be ambiguous']);
	end
	t0 = round(t0);
	keep    = find(tr>t0+1e-3);   %drop anything at/before the start instant
	yrs     = ceil(tr(keep))-1;
	uyears  = unique(yrs);
	yearidx = cell(1,numel(uyears));
	complete = true(1,numel(uyears));
	for j=1:numel(uyears),
		yearidx{j} = keep(yrs==uyears(j));
		complete(j) = tr(yearidx{j}(end))>=uyears(j)+1-1e-3;   %year must reach its end-of-year snapshot
	end
	if any(~complete),
		warning('md2tipmip:partial','Dropping %d incomplete year(s) (no end-of-year snapshot): %s',sum(~complete),num2str(uyears(~complete)));
		uyears=uyears(complete); yearidx=yearidx(complete);
	end
	nyears = numel(uyears);
	if nyears==0, error('No complete model years found in md.results.TransientSolution'); end
	if uyears(1)~=t0 || any(diff(uyears)~=1),
		warning('md2tipmip:years','Years are not consecutive from start_time=%d (first=%d, last=%d): check the output frequency/restart.',t0,uyears(1),uyears(end));
	end
	%}}}

	%Time axis: days since 0000-1-1, 365_day calendar {{{
	%state: instantaneous, registered at the end of the year
	%flux : yearly mean, registered at the middle of the year, bounds = start/end of year
	time_state     = (uyears+1)*365;
	time_flux      = uyears*365 + 365/2;
	time_flux_bnds = [uyears*365; (uyears+1)*365];
	time_initial   = t0*365;
	%}}}

	%Grid {{{
	posting = resolution_km*1000;
	gridx   = -720000 :posting: 960000;   %EPSG:3413 ISMIP grid, ascending
	gridy   = -3450000:posting:-570000;
	nx = numel(gridx); ny = numel(gridy);
	nv = md.mesh.numberofvertices;
	yts = md.constants.yts;
	fillval = single(9.969209968386869e+36);
	%}}}

	%Optional result fields {{{
	has_bmbfl = isfield(sol,'BasalforcingsFloatingiceMeltingRate');
	if ~has_bmbfl,
		warning('md2tipmip:nobmbfl','BasalforcingsFloatingiceMeltingRate not found - libmassbffl treated as 0.');
	end
	has_calv = all(isfield(sol,{'Calvingratex','Calvingratey','CalvingMeltingrate'}));
	if ~has_calv,
		warning('md2tipmip:nocalv','Calvingratex/y or CalvingMeltingrate not found - licalvf and lifmassbf will be fill value.');
	end
	has_vxavg = isfield(sol,'VxAverage');
	if ~has_vxavg,
		warning('md2tipmip:novxavg','VxAverage/VyAverage not found - using Vx/Vy for the grounding-line flux (only correct for a depth-uniform/2D model).');
	end
	%}}}

	%Variables: id, standard_name, units, field, zero_missing, is_flux {{{
	%zero_missing=true: data-request fill_policy 'forbidden' - NaN is written as 0, not fill.
	gvars = {
		'lithk',       'land_ice_thickness',                         'm',          'thickness',   true,  false;
		'orog',        'surface_altitude',                           'm',          'surface',     false, false;
		'topg',        'bedrock_altitude',                           'm',          'bed',         false, false;
		'base',        '',                                           'm',          'base',        false, false;
		'acabf',       'land_ice_surface_specific_mass_balance_flux','kg m-2 s-1', 'smb',         true,  true;
		'libmassbfgr', 'land_ice_basal_specific_mass_balance_flux',  'kg m-2 s-1', 'libmassbfgr', true,  true;
		'libmassbffl', 'land_ice_basal_specific_mass_balance_flux',  'kg m-2 s-1', 'bmb',         true,  true;
		'dlithkdt',    'tendency_of_land_ice_thickness',             'm s-1',      'dhdt',        true,  true;
		'xvelmean',    'land_ice_vertical_mean_x_velocity',          'm s-1',      'vxmean',      false, false;
		'yvelmean',    'land_ice_vertical_mean_y_velocity',          'm s-1',      'vymean',      false, false;
		'strbasemag',  'land_ice_basal_drag',                        'Pa',         'drag',        false, false;
		'licalvf',     'land_ice_specific_mass_flux_due_to_calving', 'kg m-2 s-1', 'calving',     false, true;
		'ligroundf',   '',                                           'kg m-2 s-1', 'ligroundf',   false, true;
		'lifmassbf',   '',                                           'kg m-2 s-1', 'lifmassbf',   false, true;
		'sftgif',      'land_ice_area_fraction',                     '1',          'sftgif',      true,  false;
		'sftgrf',      'grounded_ice_sheet_area_fraction',           '1',          'sftgrf',      true,  false;
		'sftflf',      'floating_ice_shelf_area_fraction',           '1',          'sftflf',      true,  false;
	};
	nvars = size(gvars,1);
	%}}}

	%Open all output files; they are filled one year at a time {{{
	h = cell(1,nvars);
	for v=1:nvars,
		h{v} = open_gridded(mkfname(gvars{v,1}),gvars{v,1},gvars{v,2},gvars{v,3},gridx,gridy,gvars{v,6},fillval,source_id,ism_id,experiment_name);
	end
	cleanupObj = onCleanup(@() close_all(h));   %close files if anything below errors (ncids do not change)
	%}}}

	drag_cap = struct('noccurrences',0,'nvertices_total',0,'worst_value',-Inf,'worst_year',[]);

	%Initial state (state variables only) {{{
	Hprev = md.geometry.thickness(1:nv);   %start-of-run thickness, used for dhdt in the first year
	if include_initial,
		fprintf('md2tipmip: gridding initial state (t=%d)\n',t0);
		[f,dc] = state_fields(md,Hprev,md.geometry.base(1:nv),md.geometry.surface(1:nv), ...
			md.initialization.vx(1:nv),md.initialization.vy(1:nv), ...
			md.mask.ice_levelset(1:nv),md.mask.ocean_levelset(1:nv),gridx,gridy);
		drag_cap = update_drag_cap(drag_cap,dc,t0);
		for v=1:nvars,
			if ~gvars{v,6},
				h{v} = append_slice(h{v},prep_slice(f.(gvars{v,4}),gvars{v,5},fillval),time_initial,[],nx,ny);
			end
		end
	end
	%}}}

	%Main loop: one model year per iteration {{{
	for j=1:nyears,
		if j==1 || j==nyears || mod(j,10)==0,
			fprintf('md2tipmip: gridding model year %d (%d/%d)\n',uyears(j),j,nyears);
		end
		kk = yearidx{j};
		ke = kk(end);   %end-of-year snapshot

		%--- state fields: end-of-year snapshot ---
		H  = sol(ke).Thickness(1:nv);
		[f,dc] = state_fields(md,H,sol(ke).Base(1:nv),sol(ke).Surface(1:nv), ...
			sol(ke).Vx(1:nv),sol(ke).Vy(1:nv), ...
			sol(ke).MaskIceLevelset(1:nv),sol(ke).MaskOceanLevelset(1:nv),gridx,gridy);
		drag_cap = update_drag_cap(drag_cap,dc,uyears(j));

		%--- flux fields: mean over all solutions saved within the year ---
		meltfl_sum = zeros(nv,1);
		smb_sum    = zeros(nv,1);
		for ib=1:numel(kk),
			if has_bmbfl,
				meltfl_sum = meltfl_sum + sol(kk(ib)).BasalforcingsFloatingiceMeltingRate(1:nv);
			end
			smb_kb = sol(kk(ib)).SmbMassBalance(end-nv+1:end);
			smb_kb(smb_kb<-1000) = 0;   %clip spurious values
			smb_sum = smb_sum + smb_kb;
		end
		nb = numel(kk);

		%libmassbfgr: no basal melt/refreeze under grounded ice in this model -> 0 everywhere
		f.libmassbfgr = zeros(nx,ny);

		%libmassbffl: floating-ice basal mass balance, 0 wherever there is no floating ice
		bmbval = -(transpose(interp_quiet(md.mesh.elements,md.mesh.x,md.mesh.y,meltfl_sum/nb,gridx,gridy,NaN))*md.materials.rho_ice/yts);
		bmbval(f.sftflf==0) = 0;
		bmbval(isnan(bmbval))    = 0;
		f.bmb = bmbval;

		%acabf: NaN (outside the mesh footprint) -> 0
		smb = interp_quiet(md.mesh.elements,md.mesh.x,md.mesh.y,smb_sum/nb,gridx,gridy,NaN);
		smb(isnan(smb)) = 0;
		f.smb = transpose(smb)*md.materials.rho_ice/yts;

		%dlithkdt: mean thickness tendency over the year = (H_end - H_start)/1 yr
		f.dhdt = transpose(interp_quiet(md.mesh.elements,md.mesh.x,md.mesh.y,H-Hprev,gridx,gridy,NaN))/yts;
		Hprev = H;

		%ligroundf: grounding-line flux from the end-of-year snapshot, per unit horizontal area
		if has_vxavg,
			vxgl = sol(ke).VxAverage(1:nv);  vygl = sol(ke).VyAverage(1:nv);
		else
			vxgl = sol(ke).Vx(1:nv);         vygl = sol(ke).Vy(1:nv);
		end
		lig_elem = compute_ligroundf(md.mesh.elements,md.mesh.x,md.mesh.y,sol(ke).MaskOceanLevelset(1:nv),H,vxgl,vygl,md.materials.rho_ice);
		f.ligroundf = transpose(interp_quiet(md.mesh.elements,md.mesh.x,md.mesh.y,lig_elem/yts,gridx,gridy,0));

		%licalvf / lifmassbf: from the end-of-year snapshot (see compute_calvingflux), outflow-only
		if has_calv,
			[calv_elem,melt_elem] = compute_calvingflux(md.mesh.elements,md.mesh.x,md.mesh.y, ...
				sol(ke).MaskIceLevelset(1:nv),H, ...
				sol(ke).Calvingratex(1:nv),sol(ke).Calvingratey(1:nv),sol(ke).CalvingMeltingrate(1:nv), ...
				sol(ke).Vx(1:nv),sol(ke).Vy(1:nv),md.materials.rho_ice);
			calv_elem = max(calv_elem,0);
			melt_elem = max(melt_elem,0);
			%ISSM convention is positive = out; CF convention for these variables is negative = mass lost
			f.calving   = transpose(interp_quiet(md.mesh.elements,md.mesh.x,md.mesh.y,-calv_elem/yts,gridx,gridy,0));
			f.lifmassbf = transpose(interp_quiet(md.mesh.elements,md.mesh.x,md.mesh.y,-melt_elem/yts,gridx,gridy,0));
		else
			f.calving   = NaN(nx,ny);
			f.lifmassbf = NaN(nx,ny);
		end

		%--- write this year ---
		for v=1:nvars,
			d = prep_slice(f.(gvars{v,4}),gvars{v,5},fillval);
			if gvars{v,6},
				h{v} = append_slice(h{v},d,time_flux(j),time_flux_bnds(:,j),nx,ny);
			else
				h{v} = append_slice(h{v},d,time_state(j),[],nx,ny);
			end
		end
	end
	%}}}

	if drag_cap.noccurrences>0,
		warning('md2tipmip:drag',['Basal drag exceeded the 1e6 Pa cap at ' num2str(drag_cap.nvertices_total) ...
			' vertex-snapshot(s) in ' num2str(drag_cap.noccurrences) ' snapshot(s); masked to NaN. Worst: ' ...
			num2str(drag_cap.worst_value) ' Pa in model year ' num2str(drag_cap.worst_year) '.']);
	end

	close_all(h);
	results.experiment_name = experiment_name;
	results.outdir          = outdir;
	results.files           = cellfun(mkfname,gvars(:,1),'UniformOutput',false);
	results.years           = uyears;
	results.time_state      = time_state;
	results.time_flux       = time_flux;
	results.time_flux_bnds  = time_flux_bnds;
	results.time_initial    = time_initial;
	results.include_initial = include_initial;

function [f,dc]=state_fields(md,H,B,S,vx,vy,icels,ocnls,xgrid,ygrid)
	%Grid all state-type fields for one snapshot. Returns (nx x ny) arrays in struct f.
	%dc summarises vertices masked by the 1e6 Pa drag cap.
	nv = md.mesh.numberofvertices;
	el = md.mesh.elements; x = md.mesh.x; y = md.mesh.y;
	yts = md.constants.yts;

	f.thickness = transpose(interp_quiet(el,x,y,H,xgrid,ygrid,NaN));
	f.base      = transpose(interp_quiet(el,x,y,B,xgrid,ygrid,NaN));
	f.surface   = transpose(interp_quiet(el,x,y,S,xgrid,ygrid,NaN));
	f.bed       = transpose(interp_quiet(el,x,y,md.geometry.bed(1:nv),xgrid,ygrid,NaN));
	f.vxmean    = transpose(interp_quiet(el,x,y,vx,xgrid,ygrid,NaN))/yts;
	f.vymean    = transpose(interp_quiet(el,x,y,vy,xgrid,ygrid,NaN))/yts;

	%Basal drag (linear Budd, p=q=1), effective pressure clamped at 0
	Neff = max(md.constants.g*(md.materials.rho_ice*H+md.materials.rho_water*B),0);
	vel  = sqrt(vx.^2+vy.^2)/yts;
	drag_mesh = md.friction.coefficient(1:nv).^2.*Neff.*vel;
	bad = find(drag_mesh>1e6);
	dc = struct('n',numel(bad),'max',0);
	if ~isempty(bad),
		dc.max = max(drag_mesh(bad));
		drag_mesh(bad) = NaN;   %data/inversion artifact: mask rather than clamp
	end
	drag = interp_quiet(el,x,y,drag_mesh,xgrid,ygrid,NaN);
	drag(drag<0) = 0;
	f.drag = transpose(drag);

	%Ice mask from the (time-varying) ice levelset
	mask = double(interp_quiet(el,x,y,-icels,xgrid,ygrid,-1)>0);
	%Grounded/floating
	g = interp_quiet(el,x,y,ocnls,xgrid,ygrid,NaN);
	g(g>0) = 1;  g(g<0) = 0;
	fl = 1-g;
	g(isnan(g)) = 0;  fl(isnan(fl)) = 0;
	f.sftgif = transpose(mask);
	f.sftgrf = transpose(g.*mask);
	f.sftflf = transpose(fl.*mask);

	%Grounded ice rests on the bed: force base=bed there and keep orog = base + lithk
	fullygrounded = f.sftgrf==1;
	f.base(fullygrounded)    = f.bed(fullygrounded);
	f.surface(fullygrounded) = f.base(fullygrounded)+f.thickness(fullygrounded);

	%fill_policy 'no_ice': velocities and drag are fill outside the ice mask
	noice = f.sftgif==0;
	f.vxmean(noice) = NaN;
	f.vymean(noice) = NaN;
	f.drag(noice)   = NaN;

function d=prep_slice(d,zero_missing,fillval)
	d = single(d);
	if zero_missing,
		d(isnan(d)) = 0;
	else
		d(isnan(d)) = fillval;
	end

function dc=update_drag_cap(dc,new,year)
	if new.n>0,
		dc.noccurrences    = dc.noccurrences+1;
		dc.nvertices_total = dc.nvertices_total+new.n;
		if new.max>dc.worst_value,
			dc.worst_value = new.max;
			dc.worst_year  = year;
		end
	end

function hh=open_gridded(fname,variable_id,standard_name,units,xcoord,ycoord,is_flux,fillval,source_id,ism_id,experiment_name)
	%Create one gridded (x,y,t) netCDF4 file with an unlimited time dimension.
	mode = bitor(netcdf.getConstant('NETCDF4'),netcdf.getConstant('CLASSIC_MODEL'));
	ncid = netcdf.create(fname,mode);
	g = netcdf.getConstant('NC_GLOBAL');
	netcdf.putAtt(ncid,g,'group',source_id);
	netcdf.putAtt(ncid,g,'model',ism_id);
	netcdf.putAtt(ncid,g,'experiment',experiment_name);
	netcdf.putAtt(ncid,g,'contact_name','Hugh Shields');                           %EDIT: set the actual contact name(s)
	netcdf.putAtt(ncid,g,'contact_email','nikolaus.h.shields.gr@dartmouth.edu');   %EDIT: set the actual contact email(s)
	netcdf.putAtt(ncid,g,'crs','epsg:3413');
	nx_id    = netcdf.defDim(ncid,'x',numel(xcoord));
	ny_id    = netcdf.defDim(ncid,'y',numel(ycoord));
	ntime_id = netcdf.defDim(ncid,'time',netcdf.getConstant('NC_UNLIMITED'));
	x_id = netcdf.defVar(ncid,'x','NC_FLOAT',nx_id);
	netcdf.putAtt(ncid,x_id,'standard_name','projection_x_coordinate');
	netcdf.putAtt(ncid,x_id,'units','m');
	netcdf.putAtt(ncid,x_id,'axis','X');
	y_id = netcdf.defVar(ncid,'y','NC_FLOAT',ny_id);
	netcdf.putAtt(ncid,y_id,'standard_name','projection_y_coordinate');
	netcdf.putAtt(ncid,y_id,'units','m');
	netcdf.putAtt(ncid,y_id,'axis','Y');
	t_id = netcdf.defVar(ncid,'time','NC_DOUBLE',ntime_id);
	netcdf.putAtt(ncid,t_id,'standard_name','time');
	netcdf.putAtt(ncid,t_id,'units','days since 0000-01-01');
	netcdf.putAtt(ncid,t_id,'calendar','365_day');
	netcdf.putAtt(ncid,t_id,'axis','T');
	b_id = -1;
	if is_flux,
		netcdf.putAtt(ncid,t_id,'bounds','time_bnds');
		nv_id = netcdf.defDim(ncid,'nv',2);
		b_id  = netcdf.defVar(ncid,'time_bnds','NC_DOUBLE',[nv_id ntime_id]);
	end
	v_id = netcdf.defVar(ncid,variable_id,'NC_FLOAT',[nx_id ny_id ntime_id]);
	netcdf.defVarDeflate(ncid,v_id,true,true,4);
	if ~isempty(standard_name),
		netcdf.putAtt(ncid,v_id,'standard_name',standard_name);
	end
	netcdf.putAtt(ncid,v_id,'units',units);
	netcdf.putAtt(ncid,v_id,'_FillValue',fillval);
	netcdf.endDef(ncid);
	netcdf.putVar(ncid,x_id,single(xcoord));
	netcdf.putVar(ncid,y_id,single(ycoord));
	hh = struct('ncid',ncid,'var_id',v_id,'time_id',t_id,'bnds_id',b_id,'is_flux',is_flux,'n',0);

function hh=append_slice(hh,data,t,bnds,nx,ny)
	%Append one time slice (and its time / bounds) to an open file.
	k = hh.n;
	netcdf.putVar(hh.ncid,hh.time_id,k,1,t);
	netcdf.putVar(hh.ncid,hh.var_id,[0 0 k],[nx ny 1],data);
	if hh.is_flux,
		netcdf.putVar(hh.ncid,hh.bnds_id,[0 k],[2 1],bnds(:));
	end
	hh.n = k+1;

function close_all(h)
	for i=1:numel(h),
		if ~isempty(h{i}),
			try, netcdf.close(h{i}.ncid); catch, end
			h{i} = [];
		end
	end

function out=interp_quiet(elements,x,y,data,xgrid,ygrid,defaultvalue)
	%Wrapper around InterpFromMeshToGrid that swallows its progress output.
	evalc('out=InterpFromMeshToGrid(elements,x,y,data,xgrid,ygrid,defaultvalue);');

function ligroundf=compute_ligroundf(elements,x,y,gl,thickness,vx,vy,rho_ice)
	%compute_ligroundf - per-element grounding-line mass flux, per unit HORIZONTAL area
	%
	%   elements          : Ne x 3 vertex indices (1-based)
	%   x, y              : Nv x 1 vertex coordinates
	%   gl                : Nv x 1 grounding mask (>0 grounded, <0 floating) - e.g.
	%                       MaskOceanLevelset or MaskGroundediceLevelset
	%   thickness, vx, vy : Nv x 1, at the SAME timestep as gl (vx,vy should be the
	%                       depth-averaged velocity for a 3D/layered mesh)
	%   rho_ice           : scalar, kg/m^3
	%
	%Returns ligroundf: Ne x 1, flux per unit horizontal area, in the same time units
	%as vx/vy (e.g. kg/m^2/yr if vx,vy are m/yr - divide by yts outside this function
	%for kg/m^2/s). Zero for elements the grounding line does not pass through.
	%
	%Geometry and the front-point ordering exactly mirror ISSM's
	%Tria::GroundinglineMassFlux (classes/Elements/Tria.cpp); the normal formula
	%exactly mirrors shared/Numerics/Normals.cpp:LineSectionNormal, so - unlike
	%Tria::GroundinglineMassFlux itself - this version divides by the element's
	%HORIZONTAL area instead of skipping the area division, giving a true
	%per-unit-area flux rather than a raw per-element mass-flux contribution.

	Ne = size(elements,1);
	ligroundf = zeros(Ne,1);
	eps_ = 1e-15;

	for e = 1:Ne,
		idx = elements(e,:);
		xyz = [x(idx), y(idx)];
		g   = gl(idx);
		g(g==0) = eps_;   %avoid exact-zero degenerate case

		if all(g>0) || all(g<0), continue; end   %grounding line does not cross this element

		h = thickness(idx);
		u = vx(idx);
		v = vy(idx);

		xyz_front = zeros(2,2);
		h_front   = zeros(2,1);
		u_front   = zeros(2,1);
		v_front   = zeros(2,1);
		pt1 = 1; pt2 = 2;   %MATLAB 1-based version of the C++ pt1=0,pt2=1

		if g(1)*g(2) > 0,        %nodes 1,2 same sign -> cross edges (3-2) and (3-1)
			s1 = g(3)/(g(3)-g(2));
			s2 = g(3)/(g(3)-g(1));
			if g(3) < 0, pt1 = 2; pt2 = 1; end
			xyz_front(pt2,:) = xyz(3,:) + s1*(xyz(2,:)-xyz(3,:));
			xyz_front(pt1,:) = xyz(3,:) + s2*(xyz(1,:)-xyz(3,:));
			h_front(pt2) = h(3)+s1*(h(2)-h(3)); h_front(pt1) = h(3)+s2*(h(1)-h(3));
			u_front(pt2) = u(3)+s1*(u(2)-u(3)); u_front(pt1) = u(3)+s2*(u(1)-u(3));
			v_front(pt2) = v(3)+s1*(v(2)-v(3)); v_front(pt1) = v(3)+s2*(v(1)-v(3));
		elseif g(2)*g(3) > 0,    %nodes 2,3 same sign -> cross edges (1-2) and (1-3)
			s1 = g(1)/(g(1)-g(2));
			s2 = g(1)/(g(1)-g(3));
			if g(1) < 0, pt1 = 2; pt2 = 1; end
			xyz_front(pt1,:) = xyz(1,:) + s1*(xyz(2,:)-xyz(1,:));
			xyz_front(pt2,:) = xyz(1,:) + s2*(xyz(3,:)-xyz(1,:));
			h_front(pt1) = h(1)+s1*(h(2)-h(1)); h_front(pt2) = h(1)+s2*(h(3)-h(1));
			u_front(pt1) = u(1)+s1*(u(2)-u(1)); u_front(pt2) = u(1)+s2*(u(3)-u(1));
			v_front(pt1) = v(1)+s1*(v(2)-v(1)); v_front(pt2) = v(1)+s2*(v(3)-v(1));
		else                      %nodes 1,3 same sign -> cross edges (2-1) and (2-3)
			s1 = g(2)/(g(2)-g(1));
			s2 = g(2)/(g(2)-g(3));
			if g(2) < 0, pt1 = 2; pt2 = 1; end
			xyz_front(pt2,:) = xyz(2,:) + s1*(xyz(1,:)-xyz(2,:));
			xyz_front(pt1,:) = xyz(2,:) + s2*(xyz(3,:)-xyz(2,:));
			h_front(pt2) = h(2)+s1*(h(1)-h(2)); h_front(pt1) = h(2)+s2*(h(3)-h(2));
			u_front(pt2) = u(2)+s1*(u(1)-u(2)); u_front(pt1) = u(2)+s2*(u(3)-u(2));
			v_front(pt2) = v(2)+s1*(v(1)-v(2)); v_front(pt1) = v(2)+s2*(v(3)-v(2));
		end

		d = xyz_front(2,:) - xyz_front(1,:);
		L = norm(d);
		if L < eps_, continue; end
		n = [d(2), -d(1)]/L;   %LineSectionNormal: normal=[dy,-dx], normalized

		%Simpson's rule (exact for this quadratic integrand): t=0, 0.5, 1
		hm = 0.5*(h_front(1)+h_front(2));
		um = 0.5*(u_front(1)+u_front(2));
		vm = 0.5*(v_front(1)+v_front(2));

		f0 = rho_ice*h_front(1)*(u_front(1)*n(1)+v_front(1)*n(2));
		f1 = rho_ice*h_front(2)*(u_front(2)*n(1)+v_front(2)*n(2));
		fm = rho_ice*hm       *(um*n(1)+vm*n(2));
		flux = L/6*(f0 + 4*fm + f1);

		%Horizontal (map-view) element area - NOT the front cross-section area
		area = 0.5*abs((xyz(1,1)-xyz(3,1))*(xyz(2,2)-xyz(1,2)) - ...
		               (xyz(1,1)-xyz(2,1))*(xyz(3,2)-xyz(1,2)));

		ligroundf(e) = flux/area;
	end

function [calvflux,meltflux]=compute_calvingflux(elements,x,y,icels,thickness,calvingratex,calvingratey,meltingrate,vx,vy,rho_ice)
	%compute_calvingflux - per-element calving-only and melt-only mass flux, per unit
	%HORIZONTAL area (fixes the front-face-area normalization ISSM's own
	%CalvingFluxLevelset/CalvingMeltingFluxLevelset use - see md2ismip7's calving
	%comments above).
	%
	%   elements                   : Ne x 3 vertex indices (1-based)
	%   x, y                       : Nv x 1 vertex coordinates
	%   icels                      : Nv x 1 ice-front mask, MaskIceLevelset (<0 ice present)
	%   thickness                  : Nv x 1
	%   calvingratex, calvingratey : Nv x 1, calving-law rate vector (Calvingratex/Calvingratey)
	%   meltingrate                : Nv x 1, frontal/undercutting melt rate MAGNITUDE (CalvingMeltingrate)
	%   vx, vy                     : Nv x 1, ice velocity - gives the melt rate a direction
	%                                (plain Vx/Vy, matching what Tria::CalvingMeltingFluxLevelset
	%                                itself uses - not the depth-averaged velocity grounding
	%                                line needs)
	%   rho_ice                    : scalar, kg/m^3
	%
	%Returns calvflux, meltflux: Ne x 1 each, flux per unit horizontal area, in the same
	%time units as calvingratex/vx (e.g. kg/m^2/yr if those are m/yr - divide by yts
	%outside this function for kg/m^2/s). Zero for elements the ice front does not cross.
	%
	%Geometry, front-point ordering and rate formulas exactly mirror ISSM's
	%Tria::CalvingFluxLevelset / Tria::CalvingMeltingFluxLevelset (classes/Elements/Tria.cpp):
	%calving-only uses (calvingratex,calvingratey); melt-only uses meltingrate projected onto
	%the local ice-velocity direction. The normal is LineSectionNormal's [dy,-dx], NEGATED
	%(Tria::CalvingFluxLevelset flips the sign after calling NormalSection - unlike
	%Tria::GroundinglineMassFlux, which does not). This function divides by the element's
	%HORIZONTAL area instead of skipping the division (Total*) or dividing by the vertical
	%ice-front face area (ISSM's own CalvingFluxLevelset/CalvingMeltingFluxLevelset), and
	%returns calving-only and melt-only separately instead of calving-only and a
	%calving+melt-combined field.
	%
	%ACCURACY NOTE: the calving-only integrand is quadratic in the segment parameter (like
	%compute_ligroundf), so the 3-point Simpson's rule below is exact for it. The melt-only
	%integrand involves meltingrate*v/|v|, a ratio of linear functions, so it is NOT
	%exactly polynomial - Simpson's rule is only an approximation there, evaluated pointwise
	%at the same 3 points ISSM's own 3-point Gauss quadrature would use, so it should be
	%comparably accurate to ISSM's own internal computation, not a downgrade from it.

	eps_ = 1e-15;
	Ne = size(elements,1);
	calvflux = zeros(Ne,1);
	meltflux = zeros(Ne,1);

	for e = 1:Ne,
		idx = elements(e,:);
		xyz = [x(idx), y(idx)];
		g   = icels(idx);
		g(g==0) = eps_;

		if all(g>0) || all(g<0), continue; end   %ice front does not cross this element

		h   = thickness(idx);
		crx = calvingratex(idx);
		cry = calvingratey(idx);
		mr  = meltingrate(idx);
		u   = vx(idx);
		v   = vy(idx);

		xyz_front = zeros(2,2);
		h_front=zeros(2,1); crx_front=zeros(2,1); cry_front=zeros(2,1);
		mr_front=zeros(2,1); u_front=zeros(2,1); v_front=zeros(2,1);
		pt1 = 1; pt2 = 2;

		if g(1)*g(2) > 0,        %nodes 1,2 same sign -> cross edges (3-2) and (3-1)
			s1 = g(3)/(g(3)-g(2));
			s2 = g(3)/(g(3)-g(1));
			if g(3) < 0, pt1 = 2; pt2 = 1; end
			xyz_front(pt2,:) = xyz(3,:) + s1*(xyz(2,:)-xyz(3,:));
			xyz_front(pt1,:) = xyz(3,:) + s2*(xyz(1,:)-xyz(3,:));
			h_front(pt2)  = h(3)+s1*(h(2)-h(3));     h_front(pt1)  = h(3)+s2*(h(1)-h(3));
			crx_front(pt2)= crx(3)+s1*(crx(2)-crx(3)); crx_front(pt1)= crx(3)+s2*(crx(1)-crx(3));
			cry_front(pt2)= cry(3)+s1*(cry(2)-cry(3)); cry_front(pt1)= cry(3)+s2*(cry(1)-cry(3));
			mr_front(pt2) = mr(3)+s1*(mr(2)-mr(3));   mr_front(pt1) = mr(3)+s2*(mr(1)-mr(3));
			u_front(pt2)  = u(3)+s1*(u(2)-u(3));       u_front(pt1)  = u(3)+s2*(u(1)-u(3));
			v_front(pt2)  = v(3)+s1*(v(2)-v(3));       v_front(pt1)  = v(3)+s2*(v(1)-v(3));
		elseif g(2)*g(3) > 0,    %nodes 2,3 same sign -> cross edges (1-2) and (1-3)
			s1 = g(1)/(g(1)-g(2));
			s2 = g(1)/(g(1)-g(3));
			if g(1) < 0, pt1 = 2; pt2 = 1; end
			xyz_front(pt1,:) = xyz(1,:) + s1*(xyz(2,:)-xyz(1,:));
			xyz_front(pt2,:) = xyz(1,:) + s2*(xyz(3,:)-xyz(1,:));
			h_front(pt1)  = h(1)+s1*(h(2)-h(1));     h_front(pt2)  = h(1)+s2*(h(3)-h(1));
			crx_front(pt1)= crx(1)+s1*(crx(2)-crx(1)); crx_front(pt2)= crx(1)+s2*(crx(3)-crx(1));
			cry_front(pt1)= cry(1)+s1*(cry(2)-cry(1)); cry_front(pt2)= cry(1)+s2*(cry(3)-cry(1));
			mr_front(pt1) = mr(1)+s1*(mr(2)-mr(1));   mr_front(pt2) = mr(1)+s2*(mr(3)-mr(1));
			u_front(pt1)  = u(1)+s1*(u(2)-u(1));       u_front(pt2)  = u(1)+s2*(u(3)-u(1));
			v_front(pt1)  = v(1)+s1*(v(2)-v(1));       v_front(pt2)  = v(1)+s2*(v(3)-v(1));
		else                      %nodes 1,3 same sign -> cross edges (2-1) and (2-3)
			s1 = g(2)/(g(2)-g(1));
			s2 = g(2)/(g(2)-g(3));
			if g(2) < 0, pt1 = 2; pt2 = 1; end
			xyz_front(pt2,:) = xyz(2,:) + s1*(xyz(1,:)-xyz(2,:));
			xyz_front(pt1,:) = xyz(2,:) + s2*(xyz(3,:)-xyz(2,:));
			h_front(pt2)  = h(2)+s1*(h(1)-h(2));     h_front(pt1)  = h(2)+s2*(h(3)-h(2));
			crx_front(pt2)= crx(2)+s1*(crx(1)-crx(2)); crx_front(pt1)= crx(2)+s2*(crx(3)-crx(2));
			cry_front(pt2)= cry(2)+s1*(cry(1)-cry(2)); cry_front(pt1)= cry(2)+s2*(cry(3)-cry(2));
			mr_front(pt2) = mr(2)+s1*(mr(1)-mr(2));   mr_front(pt1) = mr(2)+s2*(mr(3)-mr(2));
			u_front(pt2)  = u(2)+s1*(u(1)-u(2));       u_front(pt1)  = u(2)+s2*(u(3)-u(2));
			v_front(pt2)  = v(2)+s1*(v(1)-v(2));       v_front(pt1)  = v(2)+s2*(v(3)-v(2));
		end

		d = xyz_front(2,:) - xyz_front(1,:);
		L = norm(d);
		if L < eps_, continue; end
		n = [-d(2), d(1)]/L;   %LineSectionNormal=[dy,-dx], then NEGATED (matches Tria::CalvingFluxLevelset)

		%midpoint values (linear interpolation along the front - exact since h/crx/cry/mr/u/v are all P1)
		hm   = 0.5*(h_front(1)+h_front(2));
		crxm = 0.5*(crx_front(1)+crx_front(2));
		crym = 0.5*(cry_front(1)+cry_front(2));
		um   = 0.5*(u_front(1)+u_front(2));
		vm   = 0.5*(v_front(1)+v_front(2));
		mrm  = 0.5*(mr_front(1)+mr_front(2));

		%melt rate direction = local ice-velocity direction, magnitude = meltingrate,
		%evaluated pointwise at t=0, 0.5, 1 (matches Tria::CalvingMeltingFluxLevelset)
		vel0 = sqrt(u_front(1)^2+v_front(1)^2)+1e-14;
		vel1 = sqrt(u_front(2)^2+v_front(2)^2)+1e-14;
		velm = sqrt(um^2+vm^2)+1e-14;
		mrx0 = mr_front(1)*u_front(1)/vel0; mry0 = mr_front(1)*v_front(1)/vel0;
		mrx1 = mr_front(2)*u_front(2)/vel1; mry1 = mr_front(2)*v_front(2)/vel1;
		mrxm = mrm*um/velm;                 mrym = mrm*vm/velm;

		%calving-only flux (Simpson's rule - exact, quadratic integrand)
		f0c = rho_ice*h_front(1)*(crx_front(1)*n(1)+cry_front(1)*n(2));
		f1c = rho_ice*h_front(2)*(crx_front(2)*n(1)+cry_front(2)*n(2));
		fmc = rho_ice*hm       *(crxm*n(1)+crym*n(2));
		fluxc = L/6*(f0c + 4*fmc + f1c);

		%melt-only flux (Simpson's rule - approximation, see ACCURACY NOTE above)
		f0m = rho_ice*h_front(1)*(mrx0*n(1)+mry0*n(2));
		f1m = rho_ice*h_front(2)*(mrx1*n(1)+mry1*n(2));
		fmm = rho_ice*hm       *(mrxm*n(1)+mrym*n(2));
		fluxm = L/6*(f0m + 4*fmm + f1m);

		%Horizontal (map-view) element area - NOT the front cross-section area
		area = 0.5*abs((xyz(1,1)-xyz(3,1))*(xyz(2,2)-xyz(1,2)) - ...
		               (xyz(1,1)-xyz(2,1))*(xyz(3,2)-xyz(1,2)));

		calvflux(e) = fluxc/area;
		meltflux(e) = fluxm/area;
	end
