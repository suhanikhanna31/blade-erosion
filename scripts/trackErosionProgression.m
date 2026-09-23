function report = trackErosionProgression(currentData, previousCsvPath, varargin)
%TRACKEROSIONPROGRESSION Cross-check current vs. prior inspection depths.
%   report = TRACKEROSIONPROGRESSION(currentData, previousCsvPath, ...)
%
%   currentData      - struct from readErosionCsv() for the CURRENT inspection
%   previousCsvPath  - path to a prior inspection CSV in the same format
%                       (readErosionCsv-compatible). If it doesn't exist,
%                       this location has no baseline yet - reported as
%                       'available=false' rather than an error, since a
%                       turbine's very first inspection has nothing to
%                       compare against.
%
%   Name/value options:
%     'MatchTolerance_m'        (default 3)   - max radial distance (m) to
%                                 treat two readings as "the same defect"
%     'RapidThreshold_mmPerMonth' (default 0.5) - growth rate above which
%                                 a location is flagged for priority
%                                 reinspection
%
%   Returns a struct:
%     .available      - true if a prior inspection was found to compare against
%     .records(k)     - per current-record match info: radialPos, currentDepth,
%                        previousDepth, matched, growthRate_mmPerMonth, rapid
%     .anyRapid       - true if ANY location exceeds the threshold
%     .worstGrowthRate_mmPerMonth
%     .worstRadialPos_m
%     .message
%
%   Calibration note: 0.5 mm/month is an illustrative threshold, not a
%   value derived from real blade coating/erosion field data - tune it to
%   your actual erosion-rate history before using this for real scheduling
%   decisions.

    p = inputParser;
    addParameter(p, 'MatchTolerance_m', 3);
    addParameter(p, 'RapidThreshold_mmPerMonth', 0.5);
    parse(p, varargin{:});
    opt = p.Results;

    report.available = false;
    report.records = struct('radialPos_m', {}, 'currentDepth_mm', {}, ...
        'previousDepth_mm', {}, 'matched', {}, 'growthRate_mmPerMonth', {}, 'rapid', {});
    report.anyRapid = false;
    report.worstGrowthRate_mmPerMonth = NaN;
    report.worstRadialPos_m = NaN;

    if ~exist(previousCsvPath, 'file')
        report.message = 'No prior inspection on file for this blade - recording this run as the new baseline.';
        return;
    end

    previousData = readErosionCsv(previousCsvPath);
    report.available = true;

    n = numel(currentData.radial_position_m);
    worstRate = -Inf;
    worstPos = NaN;
    anyRapid = false;

    for i = 1:n
        curPos   = currentData.radial_position_m(i);
        curDepth = currentData.pitting_depth_mm(i);
        curDateNum = parseIsoDate(currentData.inspection_date{i});

        % Nearest prior reading within tolerance
        dists = abs(previousData.radial_position_m - curPos);
        [minDist, j] = min(dists);

        rec.radialPos_m = curPos;
        rec.currentDepth_mm = curDepth;

        if isempty(minDist) || minDist > opt.MatchTolerance_m
            rec.previousDepth_mm = NaN;
            rec.matched = false;
            rec.growthRate_mmPerMonth = NaN;
            rec.rapid = false;
        else
            prevDepth = previousData.pitting_depth_mm(j);
            prevDateNum = parseIsoDate(previousData.inspection_date{j});
            deltaDays = curDateNum - prevDateNum;

            rec.previousDepth_mm = prevDepth;
            rec.matched = true;

            if deltaDays <= 0
                % Guard against bad/duplicate timestamps rather than
                % dividing by zero or reporting a nonsensical negative rate
                rec.growthRate_mmPerMonth = NaN;
                rec.rapid = false;
            else
                rate = (curDepth - prevDepth) / deltaDays * 30.44; % mm/month
                rec.growthRate_mmPerMonth = rate;
                rec.rapid = rate > opt.RapidThreshold_mmPerMonth;

                if rec.rapid
                    anyRapid = true;
                end
                if rate > worstRate
                    worstRate = rate;
                    worstPos = curPos;
                end
            end
        end

        report.records(end+1) = rec; %#ok<AGROW>
    end

    report.anyRapid = anyRapid;
    if isfinite(worstRate)
        report.worstGrowthRate_mmPerMonth = worstRate;
        report.worstRadialPos_m = worstPos;
    end

    if anyRapid
        report.message = sprintf(...
            'Rapid progression detected: %.1f m span growing at %.2f mm/month (> %.2f mm/month threshold). Recommend priority reinspection.', ...
            worstPos, worstRate, opt.RapidThreshold_mmPerMonth);
    elseif isfinite(worstRate)
        report.message = sprintf(...
            'No location exceeds the %.2f mm/month threshold. Fastest-progressing point: %.1f m span at %.2f mm/month.', ...
            opt.RapidThreshold_mmPerMonth, worstPos, worstRate);
    else
        report.message = 'No matched prior readings within tolerance - cannot compute progression this run.';
    end
end

function dn = parseIsoDate(dateStr)
%PARSEISODATE Portable ISO 'yyyy-mm-dd' -> datenum for MATLAB + Octave.
    dn = datenum(dateStr, 'yyyy-mm-dd');
end
