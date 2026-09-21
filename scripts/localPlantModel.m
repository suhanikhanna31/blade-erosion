function bendingMoment = localPlantModel(t, liftFactor, dragFactor, dampingOn)
%LOCALPLANTMODEL Analytic stand-in for SimplifiedTurbineModel.slx
%   bendingMoment = LOCALPLANTMODEL(t, liftFactor, dragFactor, dampingOn)
%
%   Reproduces the qualitative behavior the Simulink plant + PID
%   pitch-damping loop would produce, driven by the physical inputs
%   (no scenario names hardcoded):
%     - Aerodynamic imbalance grows as liftFactor drops below baseline
%       and dragFactor rises above baseline (the rotor sees uneven loading
%       once per revolution as the eroded blade section passes through
%       the wind).
%     - With damping OFF, the imbalance is left uncorrected: oscillation
%       builds up over ~3 s and is sustained (structural resonance risk).
%     - With damping ON, the active pitch loop suppresses the oscillation
%       amplitude and lets it decay with a ~2.2 s time constant.
%
%   Calibration note: the gain constants below (imbalance scaling, ampU,
%   ampM, decay/growth time constants) are illustrative, tuned so the
%   3.5 mm / 80 m governing defect in data/erosion_inspection_data.csv
%   produces peaks in the same range as the project's design targets
%   (~3.1 / ~4.8 / ~3.5 MNm for Clean / Unmanaged / Managed). Replace with
%   identified plant parameters (or the real Simulink model) before using
%   this for an actual structural sign-off.
%
%   This keeps REQ-SYS-01 (fully automated run) satisfiable on any machine
%   with base MATLAB; models/build_turbine_model.m provides the real
%   Simulink block diagram for production use.

    baseLift = 1.2;
    baseDrag = 0.045;
    baseLoad = 3.1; % MNm, nominal rotor bending moment on a clean blade

    imbalance = max(0, baseLift - liftFactor) + max(0, dragFactor - baseDrag) * 4;

    if imbalance < 1e-9
        bendingMoment = baseLoad + 0.03*sin(2*pi*0.15*t) + 0.01*randnDeterministic(t, 1);
        return;
    end

    onceRevFreq = 0.9;   % Hz, 1P rotor harmonic
    twoRevFreq  = 2.3;   % Hz, 2P harmonic

    if dampingOn
        ampM = 0.32;
        tauDecay = 2.2;
        osc = ampM*imbalance*sin(2*pi*onceRevFreq*t) + 0.4*ampM*imbalance*sin(2*pi*twoRevFreq*t + 0.4);
        envelope = exp(-t/tauDecay);
        settleLoad = baseLoad + 0.2*imbalance;
        bendingMoment = settleLoad + envelope .* osc + 0.015*randnDeterministic(t, 3);
    else
        ampU = 1.25;
        growTau = 3.0;
        osc = ampU*imbalance*sin(2*pi*onceRevFreq*t) + 0.4*ampU*imbalance*sin(2*pi*twoRevFreq*t + 0.4);
        envelope = 1 - exp(-t/growTau);
        bendingMoment = baseLoad + 0.4*imbalance + envelope .* osc + 0.03*randnDeterministic(t, 2);
    end
end

function n = randnDeterministic(t, seedOffset)
    % Deterministic, dependency-free pseudo-noise for the small sensor-
    % noise-level ripple added on top of the plant response. Deliberately
    % avoids RandStream (MATLAB-only; not implemented in GNU Octave) and
    % avoids touching MATLAB's/Octave's global RNG state, so repeated runs
    % are bit-reproducible on either platform.
    %
    % This is a fixed sine-hash, not a statistically rigorous Gaussian
    % generator - adequate here since it only feeds a few-percent cosmetic
    % ripple, not anything the pass/fail requirement checks depend on.
    x = sin(t*12.9898 + seedOffset*78.233) * 43758.5453;
    n = (x - floor(x) - 0.5) * 2; % roughly in [-1, 1]
end
