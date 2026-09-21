function data = readErosionCsv(csvPath)
%READEROSIONCSV Low-level CSV parser for the erosion inspection dataset.
%   Uses fgetl/textscan instead of readtable() so it runs unmodified on
%   both MATLAB and GNU Octave (readtable is MATLAB-only).
%
%   Expected columns: radial_position_m, pitting_depth_mm, inspection_date,
%   blade_id, notes

    fid = fopen(csvPath, 'r');
    if fid < 0
        error('readErosionCsv:FileNotFound', 'Could not open %s', csvPath);
    end
    headerLine = fgetl(fid); %#ok<NASGU> % consumed to skip the header row

    raw = textscan(fid, '%f%f%s%s%s', 'Delimiter', ',');
    fclose(fid);

    data.radial_position_m = raw{1};
    data.pitting_depth_mm  = raw{2};
    data.inspection_date   = raw{3};
    data.blade_id          = raw{4};
    data.notes             = raw{5};
end
