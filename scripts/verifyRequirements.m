function result = verifyRequirements(mode, values, varargin)
%VERIFYREQUIREMENTS Dual-layer guardrail checks for the erosion pipeline.
%
%   result = VERIFYREQUIREMENTS('feasibility', erosionMatrix, 'BladeLength', L, 'MaxDepth', D)
%       Layer 1: checks the raw inspection reading is physically sane
%       before anything is fed into the plant model.
%
%   result = VERIFYREQUIREMENTS('control', [peakUnmanaged, peakManaged], 'Threshold', 0.25)
%       Layer 2: cross-references the active run's peak load against the
%       unmanaged baseline and confirms REQ-CTRL-02's suppression target.
%
%   result is a struct with fields .pass (logical) and .message (char).

    p = inputParser;
    addParameter(p, 'BladeLength', 120);
    addParameter(p, 'MaxDepth', 15);
    addParameter(p, 'Threshold', 0.25);
    parse(p, varargin{:});
    opt = p.Results;

    switch lower(mode)
        case 'feasibility'
            radialPos = values(1);
            depth     = values(2);

            if depth < 0
                result = fail('Negative pitting depth is not physically possible.');
                return;
            end
            if depth > opt.MaxDepth
                result = fail(sprintf(...
                    'Pitting depth %.2f mm exceeds the realistic sensor bound of %.1f mm (likely sensor fault).', ...
                    depth, opt.MaxDepth));
                return;
            end
            if radialPos < 0 || radialPos > opt.BladeLength
                result = fail(sprintf(...
                    'Radial position %.1f m is outside the physical blade length (0-%.0f m).', ...
                    radialPos, opt.BladeLength));
                return;
            end
            result = pass(sprintf('%.1f m / %.2f mm within bounds.', radialPos, depth));

        case 'control'
            peakUnmanaged = values(1);
            peakManaged   = values(2);

            if peakUnmanaged <= 0
                result = fail('Invalid unmanaged baseline peak (<= 0); cannot compute suppression.');
                return;
            end

            reduction = (peakUnmanaged - peakManaged) / peakUnmanaged;

            if reduction >= opt.Threshold
                result = pass(sprintf(...
                    'Suppression achieved %.1f%% (>= %.0f%% required). %.2f MNm -> %.2f MNm.', ...
                    reduction*100, opt.Threshold*100, peakUnmanaged, peakManaged));
            else
                result = fail(sprintf(...
                    'Suppression only %.1f%% (< %.0f%% required). %.2f MNm -> %.2f MNm. Flagging for manual review.', ...
                    reduction*100, opt.Threshold*100, peakUnmanaged, peakManaged));
            end

        otherwise
            error('verifyRequirements:UnknownMode', 'Unknown verification mode: %s', mode);
    end
end

function r = pass(msg)
    r.pass = true;
    r.message = msg;
end

function r = fail(msg)
    r.pass = false;
    r.message = msg;
end
