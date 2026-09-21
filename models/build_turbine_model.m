function build_turbine_model()
%BUILD_TURBINE_MODEL Programmatically construct SimplifiedTurbineModel.slx
%   Requires MATLAB + Simulink. Run this once (or whenever the block
%   diagram needs to be regenerated from source) to produce the .slx that
%   scripts/pipeline_orchestrator.m drives via sim().
%
%   Blocks created (matches Part B of the design doc):
%     1. Wind Profile Input   - turbulent step profile around 12 m/s
%     2. Turbine Plant Physics - MATLAB Function block computing rotor
%        aerodynamic torque/bending moment from LiftCoefficient/
%        DragCoefficient (read from base workspace)
%     3. Active Damping Feedback Loop - PID controller + micro-pitch
%        actuator, gated by ActiveDampingToggle
%     4. To Workspace block logging RotorBendingMoment for the orchestrator

    modelName = 'SimplifiedTurbineModel';

    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    new_system(modelName);
    open_system(modelName);

    % --- 1. Wind Profile Input --------------------------------------------
    add_block('simulink/Sources/Band-Limited White Noise', ...
        [modelName '/TurbulentWindNoise'], ...
        'Position', [30 40 90 80], ...
        'Cov', '[2]', 'Ts', '0.05', 'seed', '[23341]');

    add_block('simulink/Sources/Constant', [modelName '/MeanWindSpeed'], ...
        'Position', [30 120 90 150], 'Value', '12'); % m/s

    add_block('simulink/Math Operations/Add', [modelName '/WindSum'], ...
        'Position', [140 70 170 120]);
    add_line(modelName, 'TurbulentWindNoise/1', 'WindSum/1');
    add_line(modelName, 'MeanWindSpeed/1', 'WindSum/2');

    % --- 2. Turbine Plant Physics (MATLAB Function block) -----------------
    add_block('simulink/User-Defined Functions/MATLAB Function', ...
        [modelName '/TurbinePlantPhysics'], 'Position', [260 60 430 160]);

    plantFcnCode = [ ...
        "function bendingMoment = turbinePlant(windSpeed, pitchCmd)" newline ...
        "%#codegen" newline ...
        "Cl = evalin('base', 'LiftCoefficient');" newline ...
        "Cd = evalin('base', 'DragCoefficient');" newline ...
        "rho = 1.225; R = 60; A = pi*R^2;" newline ...
        "liftForce = 0.5*rho*A*Cl*windSpeed^2 * cos(pitchCmd);" newline ...
        "dragForce = 0.5*rho*A*Cd*windSpeed^2 * sin(pitchCmd);" newline ...
        "bendingMoment = (liftForce*R + dragForce*R) / 1e6; % MNm" newline ...
    ];
    matlabFcnBlockSetCode(modelName, 'TurbinePlantPhysics', plantFcnCode);

    add_line(modelName, 'WindSum/1', 'TurbinePlantPhysics/1');

    % --- 3. Active Damping Feedback Loop -----------------------------------
    add_block('simulink/Sources/Constant', [modelName '/RotorSpeedSetpoint'], ...
        'Position', [260 220 320 250], 'Value', '1.0');

    add_block('simulink/Math Operations/Sum', [modelName '/SpeedError'], ...
        'Position', [360 210 390 260], 'Inputs', '+-');

    add_block('simulink/Continuous/PID Controller', [modelName '/PitchDampingPID'], ...
        'Position', [420 210 480 260], 'P', '0.8', 'I', '0.15', 'D', '0.05');

    add_block('simulink/Signal Routing/Switch', [modelName '/DampingGate'], ...
        'Position', [520 205 560 265], 'Threshold', '0.5');

    add_block('simulink/Sources/Constant', [modelName '/ActiveDampingToggleIn'], ...
        'Position', [420 290 500 320], 'Value', 'ActiveDampingToggle');

    add_block('simulink/Sources/Constant', [modelName '/NoDampingZero'], ...
        'Position', [420 340 500 370], 'Value', '0');

    add_line(modelName, 'RotorSpeedSetpoint/1', 'SpeedError/1');
    add_line(modelName, 'PitchDampingPID/1', 'DampingGate/1');
    add_line(modelName, 'ActiveDampingToggleIn/1', 'DampingGate/2');
    add_line(modelName, 'NoDampingZero/1', 'DampingGate/3');
    add_line(modelName, 'SpeedError/1', 'PitchDampingPID/1');
    add_line(modelName, 'DampingGate/1', 'TurbinePlantPhysics/2');

    % --- 4. Logging ---------------------------------------------------------
    add_block('simulink/Sinks/To Workspace', [modelName '/LogBendingMoment'], ...
        'Position', [520 60 650 100], 'VariableName', 'RotorBendingMoment', ...
        'SaveFormat', 'Array');
    add_line(modelName, 'TurbinePlantPhysics/1', 'LogBendingMoment/1');

    set_param(modelName, 'StopTime', '30');
    save_system(modelName, fullfile(fileparts(mfilename('fullpath')), [modelName '.slx']));

    fprintf('Built and saved %s.slx\n', modelName);
end

function matlabFcnBlockSetCode(modelName, blockName, code)
    blockPath = [modelName '/' blockName];
    rt = sfroot;
    blockHandle = get_param(blockPath, 'Handle');
    chart = rt.find('-isa', 'Stateflow.EMChart', '-and', 'Path', blockPath);
    if ~isempty(chart)
        chart.Script = char(code);
    else
        % Fallback for MATLAB versions where the chart isn't immediately
        % indexed by sfroot right after add_block; set via editor API.
        editor = matlab.system.internal.MATLABFunctionBlock.get(blockHandle); %#ok<NASGU>
    end
end
