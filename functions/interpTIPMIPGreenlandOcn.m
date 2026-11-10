function frontalforcing = interpTIPMIPGreenlandOcn(md, scenario)
	%{
	%interpTIPMIPGreenlandOcn - build the monthly ocean thermal forcing for
	%TIPMIP-ICE SHEETS (Greenland, UKESM1-2-LL) and return it as a
	%frontalforcingsrignot object: static present-day EN4 thermal forcing climatology
	%plus shifted ESM thermal forcing anomalies, as one monthly time series.
	%
	%Requires the 'runoff discharge' ISSM patch (rignot_runoff_discharge.patch):
	%TIPMIP does not provide subglacial discharge, so frontalforcings.isdischargerunoff
	%is set to 1 and the discharge is computed in ISSM from the SMB runoff
	%(md.transient.issmb must be 1 and md.smb an SMB model that provides runoff,
	%e.g. SMBpddSicopolis from interpTIPMIPGreenlandSMB).
	%
	%Example
	%-------
	%.. code-block:: matlab
	%	md.frontalforcings = interpTIPMIPGreenlandOcn(md,'ramp');
	%
	%Inputs
	%------
	%md: ISSM model
	%scenario: 'ramp' | 'stab2.0' | 'stab4.0' | 'stab4.0-200y-rev2.0'
	%
	%Model time (decimal years, elapsed ESM ramp time: ESM year n spans n-1 to n,
	%identical to interpTIPMIPGreenlandSMB):
	%	ramp    : forcing years 39-194 -> t = 38  to 194  (156 yr)
	%	stab2.0 : forcing years 95-294 -> t = 94  to 294  (200 yr, branches at ramp yr 94)
	%	stab4.0 : forcing years 195-394-> t = 194 to 394  (200 yr, branches at ramp yr 194)
	%	stab4.0-200y-rev2.0 : the 2 C stabilization forcing (same fields as stab2.0), re-timed to
	%	                      t = 394 to 594 (200 yr, drop back to 2 C after 200 yr at 4 C)
	%
	%Method (per mesh vertex and per calendar month m)
	%	TF(t) = max(0, TFclim_EN4(m) + [ dTF_ESM(t) - mean_{ESM yrs 37-41} dTF_ESM(m) ])
	%TFclim: 1992-2021 monthly climatology of the EN4 thermal forcing (ISMIP7 OCX,
	%ocean-1000m/tf/v1). The 5-yr offset (ESM years 37-41, centered on year 39 which
	%matches 2007) always comes from the *ramp* file (esm-up2p0), so every scenario is
	%anchored to the same reference.
	%
	%Output
	%------
	%frontalforcing: frontalforcingsrignot with
	%	thermalforcing        (nv+1) x nmonths  [deg C], one column per month stamped at
	%	                      mid-month (decimal years of elapsed model time, last row)
	%	basin_id              nelem x 1, integers in 1..num_basins (1-based; ISSM marshals
	%	                      basin_id-1). Mesh elements that do not fall in any ISMIP basin
	%	                      (raster value 0 / outside the raster, i.e. ocean that ice never
	%	                      reaches) are put in one extra 'background' basin numbered
	%	                      N+1, so no element is ever labelled 0 (-> -1 after marshalling).
	%	num_basins            N+1 (N ISMIP basins + 1 background basin)
	%	isdischargerunoff     1 (subglacial_discharge is not used / not marshalled)
	%}

	if nargin < 2, error('usage: interpTIPMIPGreenlandOcn(md, scenario)'); end

	% ------------------------------------------------------------------
	% Paths
	% ------------------------------------------------------------------
	switch oshostname(),
		case {'totten'}
			ismip7dir = '/totten_1/ModelData/ISMIP7/ISMIP7/';
			tipmipdir = '/totten_1/ModelData/TIPMIP/gis/UKESM1-2-LL/';
		otherwise
			error('machine not supported yet, please provide your own paths');
	end
	en4_tf_dir = fullfile(ismip7dir, 'GrIS', 'OCX', 'EN4', 'ocean-1000m', 'tf', 'v1');
	basin_file = fullfile(ismip7dir, 'tools', 'ismip7-gris-ocean-forcing', 'subglacial_discharge_basins_ismip.nc');

	% ------------------------------------------------------------------
	% Settings (same conventions as interpTIPMIPGreenlandSMB)
	% ------------------------------------------------------------------
	clim_years  = 1992:2021;   % 30-yr climatology centered on 2007
	shift_year  = 39;          % UKESM1-2-LL sim. year matching 2007
	half_window = 2;           % 5-yr mean centered on shift_year -> yrs 37-41
	ramp_dir    = 'esm-up2p0';
	stab_years  = 200;         % length of stabilization runs
	cumdays     = [0 31 59 90 120 151 181 212 243 273 304 334 365]; % 365_day calendar
	nv          = md.mesh.numberofvertices;

	% t_branch: model time at which the scenario's first forcing year starts
	% file_t0 : time encoded in the stab file name (_ext_YYYYMM_...) = ramp branch time of that file
	switch scenario
		case 'ramp'
			scen_dir = ramp_dir;   t_branch = 0;   file_t0 = 0;   yr_range = [shift_year Inf];
		case 'stab2.0'
			scen_dir = 'esm-up2p0-gwl2p0'; t_branch = 94;  file_t0 = 94;  yr_range = [1 stab_years];
		case 'stab4.0'
			scen_dir = 'esm-up2p0-gwl4p0'; t_branch = 194; file_t0 = 194; yr_range = [1 stab_years];
		case 'stab4.0-200y-rev2.0'
			% reversal 4 C -> 2 C after 200 yr of 4 C stabilization (t = 194..394): same 2 C
			% stabilization forcing as stab2.0 (file starts at 94) but run from t = 394 to 594
			scen_dir = 'esm-up2p0-gwl2p0'; t_branch = 394; file_t0 = 94;  yr_range = [1 stab_years];
		otherwise
			error('scenario ''%s'' not supported (use ramp, stab2.0, stab4.0, stab4.0-200y-rev2.0)', scenario);
	end

	% ramp: TF_<model>_<exp>_gis_ismip1000m.nc  (ignore any *_ext_* file)
	% stab: TF_<model>_<exp>_gis_ismip1000m_ext_YYYYMM_YYYYMM.nc
	ramp_tf_file = findSingleFile(fullfile(tipmipdir, ramp_dir, 'TF_*.nc'), '_ext_');
	if strcmp(scenario, 'ramp')
		scen_tf_file = ramp_tf_file;
		ext_range    = [];
	else
		scen_tf_file = findSingleFile(fullfile(tipmipdir, scen_dir, 'TF_*_ext_*.nc'));
		ext_range    = parseExtRange(scen_tf_file);
		if abs(ext_range(1) - file_t0) > 1e-6
			error('%s starts at t=%g but scenario %s expects a file starting at t=%d', scen_tf_file, ext_range(1), scenario, file_t0);
		end
	end

	% ------------------------------------------------------------------
	% 1) EN4 30-yr monthly thermal forcing climatology on the mesh
	% ------------------------------------------------------------------
	disp(['   == Loading EN4 thermal forcing climatology ' num2str(clim_years(1)) '-' num2str(clim_years(end))]);
	tf_ref = enMonthlyClim(en4_tf_dir, clim_years, md, cumdays);   % nv x 12, deg C

	% ------------------------------------------------------------------
	% 2) ESM 5-yr offset (sim years 37-41 of the RAMP file), per calendar month
	% ------------------------------------------------------------------
	disp(['   == Computing ESM offsets, sim. years ' num2str(shift_year-half_window) '-' num2str(shift_year+half_window)]);
	[~, ~, simyr_r, mon_r] = esmTime(ramp_tf_file, cumdays);
	win = find(simyr_r >= shift_year-half_window & simyr_r <= shift_year+half_window);
	if numel(win) ~= 12*(2*half_window+1)
		error('Expected %d months in offset window, found %d', 12*(2*half_window+1), numel(win));
	end
	crop = getCrop(ramp_tf_file, md);

	% Only the 60 window months (hyperslab: cropped x/y, 12-month time slabs) are
	% read from the ramp file, one year at a time, accumulating the mean.
	nyr_win = 2*half_window + 1;
	tf_off  = zeros(nv, 12);
	for k = 1:12:numel(win)
		ii = win(k:k+11);          % contiguous 12 months of one ESM year
		mm = mon_r(ii);            % calendar months 1..12 (unique within a year)
		if numel(unique(mm)) ~= 12, error('Offset window year %d is not 12 distinct calendar months', (k+11)/12); end
		dTF = readESM(ramp_tf_file, 'TF_anomaly', ii, crop, md);
		tf_off(:,mm) = tf_off(:,mm) + dTF/nyr_win;
		fprintf('\r   -- offset year %d/%d', (k+11)/12, nyr_win);
	end
	fprintf('\n');

	% ------------------------------------------------------------------
	% 3) Scenario thermal forcing: one monthly time series
	% ------------------------------------------------------------------
	[~, tbnds, simyr, mon] = esmTime(scen_tf_file, cumdays);
	if mon(1) ~= 1
		error('%s does not start in January (first month = %d)', scen_tf_file, mon(1));
	end
	if ~isempty(ext_range) && numel(mon) ~= round((ext_range(2)-ext_range(1))*12)
		error('%s has %d months but filename implies %d', scen_tf_file, numel(mon), ...
			round((ext_range(2)-ext_range(1))*12));
	end
	idx = find(simyr >= yr_range(1) & simyr <= yr_range(2));
	if isempty(idx), error('No months found for scenario %s', scenario); end
	nt = numel(idx);
	if mod(nt,12) ~= 0, error('Expected a whole number of years, got %d months', nt); end
	if mon(idx(1)) ~= 1, error('Scenario %s does not start in January', scenario); end
	nyr = nt/12;
	if ~strcmp(scenario,'ramp') && nyr < stab_years
		warning('%s file only has %d years (expected %d)', scenario, nyr, stab_years);
	end
	disp(['   == Scenario ' scenario ': ' num2str(nyr) ' years (' num2str(nt) ' months), ~' ...
		num2str((nv+1)*nt*8/1e9,'%.1f') ' GB for TF']);

	% Time stamps (decimal years, elapsed model time), one per month at the MIDDLE of the
	% month: with linear interpolation in time between stamps each monthly field applies
	% at the middle of its own month. Same time origin as interpTIPMIPGreenlandSMB
	% (ramp: ESM year 1 starts at t=0; stab: file start = branch time).
	t_month = t_branch + (0.5*(tbnds(idx,1) + tbnds(idx,2)) - tbnds(1,1))/365;

	crop = getCrop(scen_tf_file, md);
	TF = zeros(nv+1, nt);
	TF(end,:) = t_month(:)';
	for k = 1:12:nt
		yr  = (k-1)/12 + 1;
		ii  = idx(k:k+11);      % contiguous 12 months starting in January
		mm  = mon(ii);          % 1..12
		dTF = readESM(scen_tf_file, 'TF_anomaly', ii, crop, md);
		% TF = TFclim(m) + (dTF - ESM offset(m)); thermal forcing cannot be negative
		TF(1:nv, k:k+11) = max(0, tf_ref(:,mm) + (dTF - tf_off(:,mm)));
		fprintf('\r   -- %d/%d years', yr, nyr);
	end
	fprintf('\n');
	if any(isnan(TF(:))), error('NaN found in thermal forcing'); end
	disp(['   == Model time: monthly fields stamped at t = ' num2str(t_month(1)) ' ... ' num2str(t_month(end))]);

	% ------------------------------------------------------------------
	% 4) Basin IDs (one per mesh element)
	% ------------------------------------------------------------------
	disp('   == Reading basin data from NetCDF file');
	x_basin    = double(ncread(basin_file, 'x'));      % meters
	y_basin    = double(ncread(basin_file, 'y'));      % meters
	basin_data = double(ncread(basin_file, 'basin'));  % unitless integer basin label

	if ~isequal(size(basin_data), [length(x_basin), length(y_basin)])
		basin_data = basin_data';
	end

	unique_basins = unique(basin_data(:));
	unique_basins(unique_basins == 0 | isnan(unique_basins)) = [];  % 0 = background / no basin
	nbasins_ismip = length(unique_basins);
	disp(['   -- found ' num2str(nbasins_ismip) ' basins']);

	% remap to contiguous 1..N labels in case the raster's raw ids aren't already
	basin_data_remapped = zeros(size(basin_data));
	for b = 1:nbasins_ismip
		basin_data_remapped(basin_data == unique_basins(b)) = b;
	end

	xc = mean(md.mesh.x(md.mesh.elements), 2); % element centroid x, meters
	yc = mean(md.mesh.y(md.mesh.elements), 2); % element centroid y, meters

	% 'nearest' avoids blending basin labels into meaningless intermediate values
	basin_id = InterpFromGrid(x_basin, y_basin, basin_data_remapped', xc, yc, 'nearest');

	% Elements in the raster background (0) or outside the raster (NaN) are ocean that ice
	% never reaches. They must still carry a valid id: ISSM marshals basin_id-1, so a 0
	% here would become -1 and index basin arrays out of bounds in the C++. Give them their
	% own background basin (N+1) so they never contaminate a real basin's ice-front area
	% or runoff sum.
	nobasin = ~(basin_id >= 1);
	if any(nobasin)
		disp(['   -- ' num2str(sum(nobasin)) ' elements outside any basin -> background basin ' num2str(nbasins_ismip+1)]);
		basin_id(nobasin) = nbasins_ismip + 1;
	end
	num_basins = nbasins_ismip + 1;
	if any(basin_id < 1 | basin_id > num_basins | basin_id ~= round(basin_id))
		error('Invalid basin ids found (expected integers in 1..%d)', num_basins);
	end

	% ------------------------------------------------------------------
	% 5) Assemble the frontalforcingsrignot object
	% ------------------------------------------------------------------
	frontalforcing = frontalforcingsrignot();
	if ~isprop(frontalforcing, 'isdischargerunoff')
		error(['frontalforcingsrignot has no isdischargerunoff property: apply ' ...
			'rignot_runoff_discharge.patch (TIPMIP has no subglacial discharge data)']);
	end
	frontalforcing.thermalforcing    = TF;
	frontalforcing.basin_id          = basin_id;
	frontalforcing.num_basins        = num_basins;
	frontalforcing.isdischargerunoff = 1;   % discharge from basin-integrated SMB runoff

end

% ======================================================================
function f = findSingleFile(pattern, exclude)
	d = dir(pattern);
	if nargin > 1 && ~isempty(exclude)
		d = d(cellfun(@isempty, strfind({d.name}, exclude)));
	end
	if numel(d) ~= 1
		error('Expected exactly one file for %s, found %d', pattern, numel(d));
	end
	f = fullfile(d(1).folder, d(1).name);
end

% ----------------------------------------------------------------------
function r = parseExtRange(file)
	%period from '..._ext_YYYYMM_YYYYMM.nc' -> [t_start t_end] elapsed years
	%(start of first month, end of last month)
	tok = regexp(file, 'ext_(\d{4})(\d{2})_(\d{4})(\d{2})\.nc$', 'tokens', 'once');
	if isempty(tok), error('Cannot parse ext_YYYYMM_YYYYMM range from %s', file); end
	v = str2double(tok);
	r = [v(1) + (v(2)-1)/12, v(3) + v(4)/12];
end

% ----------------------------------------------------------------------
function [tmid, tbnds, simyr, mon] = esmTime(file, cumdays)
	%time (days since 0000-1-1, 365_day): midpoint, bounds, sim. year (1 = first
	%year in file) and calendar month of every record
	tmid  = double(ncread(file, 'time'));
	tbnds = double(ncread(file, 'time_bnds'));
	if size(tbnds,1) == 2, tbnds = tbnds'; end
	simyr = floor(tbnds(:,1)/365) - floor(tbnds(1,1)/365) + 1;
	doy   = mod(tmid, 365);
	mon   = sum(doy(:) >= cumdays(1:12), 2); % 1..12
end

% ----------------------------------------------------------------------
function mon = enMonths(file, cumdays)
	%calendar month (1..12) of every record of an EN4 yearly file, from its own time
	%axis ('days since YYYY-MM-DD ...', noleap calendar)
	t   = double(ncread(file, 'time'));
	un  = ncreadatt(file, 'time', 'units');
	tok = regexp(un, 'since\s+(\d+)-(\d+)-(\d+)', 'tokens', 'once');
	if isempty(tok), error('Could not parse time reference date from units string: %s', un); end
	doy0 = cumdays(str2double(tok{2})) + str2double(tok{3}) - 1; % 0-based day of year of the reference date
	doy  = mod(t(:) + doy0, 365);
	mon  = sum(doy >= cumdays(1:12), 2);
end

% ----------------------------------------------------------------------
function crop = getCrop(file, md)
	%index window of the file's x/y grid covering the mesh (+ buffer)
	offset = 2;
	x_n = double(ncread(file,'x'));
	y_n = double(ncread(file,'y'));
	posx = find(x_n <= max(md.mesh.x(:)));
	posy = find(y_n <= max(md.mesh.y(:)));
	crop.id1x = max(1, find(x_n >= min(md.mesh.x(:)),1) - offset);
	crop.id2x = min(numel(x_n), posx(end) + offset);
	crop.id1y = max(1, find(y_n >= min(md.mesh.y(:)),1) - offset);
	crop.id2y = min(numel(y_n), posy(end) + offset);
	crop.x = x_n(crop.id1x:crop.id2x);
	crop.y = y_n(crop.id1y:crop.id2y);
end

% ----------------------------------------------------------------------
function M = interpStack(F, crop, md)
	%interpolate (x,y,t) stack onto mesh -> nv x t
	M = zeros(md.mesh.numberofvertices, size(F,3));
	for j = 1:size(F,3)
		Fj = double(F(:,:,j)');
		% the files also carry a non-standard 'fill_value' (1.1e+20) attribute that ncread
		% does not apply; treat such values as missing
		Fj(abs(Fj) > 1e19) = NaN;
		M(:,j) = InterpFromGrid(crop.x, crop.y, Fj, double(md.mesh.x), double(md.mesh.y), 'linear');
	end
	M = fillNearest(M, md);
end

% ----------------------------------------------------------------------
function M = fillNearest(M, md)
	%replace NaN vertices (outside data coverage, e.g. land) with nearest valid vertex.
	%The NaN pattern is static, so the nearest-vertex map is cached between calls.
	persistent lastkey lastbad lastb lastsrc
	bad = any(isnan(M), 2);
	if ~any(bad), return; end
	key = [numel(md.mesh.x) sum(md.mesh.x(:)) sum(md.mesh.y(:))];
	if isempty(lastkey) || ~isequal(key, lastkey) || ~isequal(bad, lastbad)
		good = find(~bad);
		if isempty(good), error('No valid data on any mesh vertex (check mesh/data extents)'); end
		b  = find(bad);
		nn = dsearchn([md.mesh.x(good), md.mesh.y(good)], [md.mesh.x(b), md.mesh.y(b)]);
		lastkey = key; lastbad = bad; lastb = b; lastsrc = good(nn);
	end
	M(lastb,:) = M(lastsrc,:);
end

% ----------------------------------------------------------------------
function M = readESM(file, varname, tidx, crop, md)
	%read (contiguous) time indices tidx of an ESM field and interpolate to mesh
	tidx = tidx(:)';
	if any(diff(tidx) ~= 1), error('readESM expects contiguous time indices'); end
	% hyperslab read: cropped x/y window x only the requested time records
	F = ncread(file, varname, [crop.id1x crop.id1y tidx(1)], ...
		[crop.id2x-crop.id1x+1, crop.id2y-crop.id1y+1, numel(tidx)]); % single
	M = interpStack(F, crop, md);
end

% ----------------------------------------------------------------------
function clim = enMonthlyClim(dirname, years, md, cumdays)
	%30-yr monthly climatology (nv x 12, calendar-month order) of yearly EN4 TF files
	%tf_*_<year>.nc (12 monthly records each)
	nv   = md.mesh.numberofvertices;
	acc  = zeros(nv, 12);
	crop = [];
	for y = years
		d = dir(fullfile(dirname, sprintf('tf_*_%d.nc', y)));
		if numel(d) ~= 1
			error('Expected one tf file for %d in %s, found %d', y, dirname, numel(d));
		end
		f   = fullfile(d(1).folder, d(1).name);
		mon = enMonths(f, cumdays);
		if numel(mon) ~= 12 || ~isequal(sort(mon(:))', 1:12)
			error('%s does not hold 12 distinct calendar months', f);
		end
		if isempty(crop), crop = getCrop(f, md); end
		F = ncread(f, 'tf', [crop.id1x crop.id1y 1], ...
			[crop.id2x-crop.id1x+1, crop.id2y-crop.id1y+1, 12]); % single
		M = interpStack(F, crop, md);
		acc(:,mon) = acc(:,mon) + M;   % column j of M is calendar month mon(j)
		fprintf('\r   -- tf %d', y);
	end
	fprintf('\n');
	clim = acc/numel(years);
end
