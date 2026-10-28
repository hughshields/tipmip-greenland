function forcing = interpTIPMIPGreenlandSMB(md, scenario)
	%{
	%interpTIPMIPGreenlandSMB - build monthly 2 m air temperature and precip
	%forcing for TIPMIP-ICE SHEETS (Greenland, UKESM1-2-LL) from a present-day
	%(2007) RACMO climatology plus shifted ESM anomalies/ratios.
	%
	%Example
	%-------
	%.. code-block:: matlab
	%	f = interpTIPMIPGreenlandSMB(md,'ramp');
	%	f = interpTIPMIPGreenlandSMB(md,'stab2.0');
	%	f = interpTIPMIPGreenlandSMB(md,'stab4.0');
	%
	%Inputs
	%------
	%md: ISSM model
	%scenario: 'ramp' | 'stab2.0' | 'stab4.0'
	%
	%Model time (decimal years, elapsed ESM ramp time: ESM year n spans n-1 to n,
	%matching Table 2 of the TIPMIP-ICE SHEETS protocol):
	%	ramp    : forcing years 39-194 -> t = 38  to 194  (156 yr)
	%	stab2.0 : forcing years 95-294 -> t = 94  to 294  (200 yr, branches at ramp yr 94)
	%	stab4.0 : forcing years 195-394-> t = 194 to 394  (200 yr, branches at ramp yr 194)
	%
	%Method (per grid vertex and per calendar month m)
	%	T(t) = Tref_RACMO(m) + [ dT_ESM(t) - mean_{ESM yrs 37-41} dT_ESM(m) ]
	%	P(t) = Pref_RACMO(m) * [ eps_ESM(t) / mean_{ESM yrs 37-41} eps_ESM(m) ]
	%Tref/Pref: 1992-2021 RACMO2.3p2-ERA monthly climatologies (2 m air temperature
	%'tas' and 'pr'). The offset always comes from the *ramp* file (esm-up2p0).
	%
	%Output (struct)
	%------
	%forcing.tas      (nv+1) x nt  K, last row = time (decimal years)
	%forcing.pr       (nv+1) x nt  m ice eq. / yr, last row = time
	%forcing.month    1 x nt       calendar month (1-12) of each column
	%forcing.tas_ref, forcing.pr_ref   nv x 12 reference climatologies (K, m ice/yr)
	%forcing.tas_off, forcing.pr_off   nv x 12 ESM offsets (K, ratio)
	%}

	if nargin < 2, error('usage: interpTIPMIPGreenlandSMB(md, scenario)'); end

	% ------------------------------------------------------------------
	% Paths
	% ------------------------------------------------------------------
	switch oshostname(),
		case {'totten'}
			ismip7dir = '/totten_1/ModelData/ISMIP7/ISMIP7/GrIS/OCX/RACMO2.3p2-ERA/SDBN1-1000m/';
			tipmipdir = '/totten_1/ModelData/TIPMIP/gis/UKESM1-2-LL/';
		otherwise
			error('machine not supported yet, please provide your own paths');
	end
	pr_clim_dir  = fullfile(ismip7dir, 'pr',  'v1');
	tas_clim_dir = fullfile(ismip7dir, 'tas', 'v1');

	% ------------------------------------------------------------------
	% Settings
	% ------------------------------------------------------------------
	clim_years  = 1992:2021;   % 30-yr climatology centered on 2007
	shift_year  = 39;          % UKESM1-2-LL sim. year matching 2007 (0.89 C)
	half_window = 2;           % 5-yr mean centered on shift_year -> yrs 37-41
	ramp_dir    = 'esm-up2p0';
	stab_years  = 200;         % length of stabilization runs
	cumdays     = [0 31 59 90 120 151 181 212 243 273 304 334 365]; % 365_day calendar
	kg2m_ice_yr = md.constants.yts/md.materials.rho_ice;            % kg m-2 s-1 -> m ice yr-1

	switch scenario
		case 'ramp'
			scen_dir = ramp_dir;   t_branch = 0;   yr_range = [shift_year Inf];
		case 'stab2.0'
			scen_dir = 'esm-up2p0-gwl2p0'; t_branch = 94;  yr_range = [1 stab_years];
		case 'stab4.0'
			scen_dir = 'esm-up2p0-gwl4p0'; t_branch = 194; yr_range = [1 stab_years];
		otherwise
			error('scenario ''%s'' not supported (use ramp, stab2.0, stab4.0)', scenario);
	end

	ramp_pr_file  = findSingleFile(fullfile(tipmipdir, ramp_dir, 'pr_*.nc'));
	ramp_tas_file = findSingleFile(fullfile(tipmipdir, ramp_dir, 'tas_*.nc'));
	if strcmp(scenario, 'ramp')
		scen_pr_file  = ramp_pr_file;
		scen_tas_file = ramp_tas_file;
		ext_range     = [];
	else
		% stab files: <var>_UKESM1-2-LL_<exp>_gis_ismip1000m_ext_YYYYMM_YYYYMM.nc
		% (zero-indexed elapsed model years; 009401_029312 = Jan of yr 94 .. Dec of yr 293)
		scen_pr_file  = findSingleFile(fullfile(tipmipdir, scen_dir, 'pr_*_ext_*.nc'));
		scen_tas_file = findSingleFile(fullfile(tipmipdir, scen_dir, 'tas_*_ext_*.nc'));
		rng_pr  = parseExtRange(scen_pr_file);
		rng_tas = parseExtRange(scen_tas_file);
		if any(abs(rng_pr - rng_tas) > 1e-6)
			error('pr and tas stab files cover different periods: %s vs %s', scen_pr_file, scen_tas_file);
		end
		if abs(rng_pr(1) - t_branch) > 1e-6
			error('%s starts at t=%g but %s should branch at t=%d', scen_pr_file, rng_pr(1), scenario, t_branch);
		end
		ext_range = rng_pr; % [t_start t_end] in elapsed years
	end

	% ------------------------------------------------------------------
	% 1) RACMO 30-yr monthly climatologies on the mesh
	% ------------------------------------------------------------------
	disp(['   == Loading RACMO2.3p2-ERA climatology ' num2str(clim_years(1)) '-' num2str(clim_years(end))]);
	tas_ref = racmoMonthlyClim(tas_clim_dir, 'tas', clim_years, md);        % K
	pr_ref  = racmoMonthlyClim(pr_clim_dir,  'pr',  clim_years, md);        % kg m-2 s-1
	pr_ref  = pr_ref*kg2m_ice_yr;                                           % m ice eq. yr-1

	% ------------------------------------------------------------------
	% 2) ESM 5-yr offset (sim years 37-41 of the RAMP file), per calendar month
	% ------------------------------------------------------------------
	disp(['   == Computing ESM offsets, sim. years ' num2str(shift_year-half_window) '-' num2str(shift_year+half_window)]);
	[~, ~, simyr_r, mon_r] = esmTime(ramp_tas_file, cumdays);
	win = find(simyr_r >= shift_year-half_window & simyr_r <= shift_year+half_window);
	if numel(win) ~= 12*(2*half_window+1)
		error('Expected %d months in offset window, found %d', 12*(2*half_window+1), numel(win));
	end
	crop = getCrop(ramp_tas_file, md);

	% Only the 60 window months (hyperslab: cropped x/y, 12-month time slabs) are
	% ever read from the ~40 GB files, one year at a time, accumulating the mean.
	nyr_win = 2*half_window + 1;
	tas_off = zeros(md.mesh.numberofvertices, 12);
	pr_off  = zeros(md.mesh.numberofvertices, 12);
	for k = 1:12:numel(win)
		ii = win(k:k+11);          % contiguous 12 months of one ESM year
		mm = mon_r(ii);            % calendar months 1..12 (unique within a year)
		dT  = readESM(ramp_tas_file, 'tas_anomaly', ii, crop, md);
		eps = readESM(ramp_pr_file,  'pr_ratio',    ii, crop, md);
		tas_off(:,mm) = tas_off(:,mm) + dT/nyr_win;
		pr_off(:,mm)  = pr_off(:,mm)  + eps/nyr_win;
		fprintf('\r   -- offset year %d/%d', (k+11)/12, nyr_win);
	end
	fprintf('\n');
	pr_off(pr_off <= 0) = 1; % guard against divide-by-zero

	% ------------------------------------------------------------------
	% 3) Scenario time series
	% ------------------------------------------------------------------
	[tmid, tbnds, simyr, mon] = esmTime(scen_tas_file, cumdays);
	if mon(1) ~= 1
		error('%s does not start in January (first month = %d)', scen_tas_file, mon(1));
	end
	if ~isempty(ext_range) && numel(tmid) ~= round((ext_range(2)-ext_range(1))*12)
		error('%s has %d months but filename implies %d', scen_tas_file, numel(tmid), ...
			round((ext_range(2)-ext_range(1))*12));
	end
	idx = find(simyr >= yr_range(1) & simyr <= yr_range(2));
	if isempty(idx), error('No months found for scenario %s', scenario); end
	if ~strcmp(scenario,'ramp') && numel(idx) < 12*stab_years
		warning('%s file only has %d years (expected %d)', scenario, numel(idx)/12, stab_years);
	end
	nt = numel(idx);
	nv = md.mesh.numberofvertices;
	disp(['   == Scenario ' scenario ': ' num2str(nt/12) ' years, ~' num2str(2*nt*nv*8/1e9,'%.1f') ' GB for T+P']);

	[~, ~, ~, mon_p] = esmTime(scen_pr_file, cumdays);
	if numel(mon_p) ~= numel(mon) || any(mon_p ~= mon)
		error('pr and tas files in %s have different time axes', scen_dir);
	end

	crop = getCrop(scen_tas_file, md);
	tas = zeros(nv+1, nt);
	pr  = zeros(nv+1, nt);
	for k = 1:12:nt
		kk  = k:min(k+11, nt);
		ii  = idx(kk);
		mm  = mon(ii);
		dT  = readESM(scen_tas_file, 'tas_anomaly', ii, crop, md);
		eps = readESM(scen_pr_file,  'pr_ratio',    ii, crop, md);
		tas(1:nv,kk) = tas_ref(:,mm) + (dT - tas_off(:,mm));
		pr(1:nv,kk)  = pr_ref(:,mm) .* (eps ./ pr_off(:,mm));
		fprintf('\r   -- %d/%d months', kk(end), nt);
	end
	fprintf('\n');

	% model time: elapsed years. Ramp: file starts at ESM year 1 -> t=0 at start of
	% year 1 (so forcing year 39 starts at t=38). Stab: file start = branch time.
	time_vec = t_branch + (tmid(idx) - tbnds(1,1))/365;
	tas(end,:) = time_vec(:)';
	pr(end,:)  = time_vec(:)';
	disp(['   == Model time covers t = ' num2str(t_branch + (tbnds(idx(1),1)-tbnds(1,1))/365) ...
		' to ' num2str(t_branch + (tbnds(idx(end),2)-tbnds(1,1))/365)]);

	forcing.tas     = tas;
	forcing.pr      = pr;
	forcing.month   = mon(idx)';
	forcing.tas_ref = tas_ref;
	forcing.pr_ref  = pr_ref;
	forcing.tas_off = tas_off;
	forcing.pr_off  = pr_off;
end

% ======================================================================
function f = findSingleFile(pattern)
	d = dir(pattern);
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
		M(:,j) = InterpFromGrid(crop.x, crop.y, double(F(:,:,j)'), double(md.mesh.x), double(md.mesh.y));
	end
	M = fillNearest(M, md);
end

% ----------------------------------------------------------------------
function M = fillNearest(M, md)
	%replace NaN vertices (outside data coverage) with nearest valid vertex
	bad = any(isnan(M), 2);
	if ~any(bad), return; end
	good = find(~bad);
	b    = find(bad);
	nn   = dsearchn([md.mesh.x(good), md.mesh.y(good)], [md.mesh.x(b), md.mesh.y(b)]);
	M(b,:) = M(good(nn),:);
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
function clim = racmoMonthlyClim(dirname, varname, years, md)
	%30-yr monthly climatology (nv x 12) of yearly RACMO files <var>_*_<year>.nc
	nv  = md.mesh.numberofvertices;
	acc = zeros(nv, 12);
	crop = [];
	for y = years
		d = dir(fullfile(dirname, sprintf('%s_*_%d.nc', varname, y)));
		if numel(d) ~= 1
			error('Expected one %s file for %d in %s, found %d', varname, y, dirname, numel(d));
		end
		f = fullfile(d(1).folder, d(1).name);
		if isempty(crop), crop = getCrop(f, md); end
		F = ncread(f, varname, [crop.id1x crop.id1y 1], ...
			[crop.id2x-crop.id1x+1, crop.id2y-crop.id1y+1, 12]); % single
		acc = acc + interpStack(F, crop, md);
		fprintf('\r   -- %s %d', varname, y);
	end
	fprintf('\n');
	clim = acc/numel(years);
end
