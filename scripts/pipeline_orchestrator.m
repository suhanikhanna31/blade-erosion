%% pipeline_orchestrator.m
% Closed-Loop Blade Erosion Integrity & Active Control Pipeline
% Master automation script (Model-Based Design orchestrator)
%
% Workflow:
%   1. Ingest inspection CSV
%   2. Layer-1 feasibility check on the raw data
%   3. Translate pitting depth -> degraded aerodynamic coefficients
%   4. Drive the plant model for three scenarios (Clean / Unmanaged / Managed)
%      - Uses Simulink model 'SimplifiedTurbineModel.slx' if it exists and
%        Simulink is licensed on this machine.
%      - Otherwise falls back to an analytic plant (localPlantModel.m) that
%        reproduces the same qualitative dynamics, so the whole pipeline is
%        runnable end-to-end on any machine with plain MATLAB.
%   5. Layer-2 guardrail: verify REQ-CTRL-02 (>=25% suppression)
%   6. Export peak load boundary condition for ANSYS
%   7. Generate report figures + pass/fail dashboard
%   8. Post a JSON run summary to an automation webhook (n8n / Zapier),
%      if one is configured, so downstream alerting/ticketing/logging can
%      run without anyone watching the MATLAB console (see automation/).
%
% Author: Blade Integrity Engineering Pipeline
clear; clc; close all;

% --- Automation webhook (n8n / Zapier) ---------------------------------
% Paste an n8n Webhook node's Production URL, or a Zapier "Webhooks by
% Zapier" Catch Hook URL, here to get an automatic notification/log/ticket
% every time this pipeline runs. Leave empty ('') to disable - the
% pipeline runs identically either way. See automation/README_automation.md.
webhookUrl = '';   % e.g. 'https://your-n8n-host/webhook/blade-erosion-pipeline'

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));   % .../blade_erosion_pipeline
addpath(fullfile(projectRoot, 'scripts'));
dataDir    = fullfile(projectRoot, 'data');
figDir     = fullfile(projectRoot, 'reports', 'figures');
feaDir     = fullfile(projectRoot, 'fea');
if ~exist(figDir, 'dir'); mkdir(figDir); end

fprintf('=== Closed-Loop Blade Erosion Pipeline: START ===\n');

%% 1. Ingest inspection data ------------------------------------------------
% Uses low-level textscan rather than readtable() so this runs unmodified
% on both MATLAB and GNU Octave (readtable is MATLAB-only).
csvPath = fullfile(dataDir, 'erosion_inspection_data.csv');
inspection = readErosionCsv(csvPath);
fprintf('Ingested %d inspection records from %s\n', numel(inspection.radial_position_m), csvPath);

% Select the governing defect: worst pitting depth on the record (this is
% the one that drives the control/structural check).
[maxDepth, idx] = max(inspection.pitting_depth_mm);
erosionMatrix = [inspection.radial_position_m(idx), inspection.pitting_depth_mm(idx)];
fprintf('Governing defect: %.1f m span, %.2f mm pitting depth (blade %s)\n', ...
    erosionMatrix(1), erosionMatrix(2), inspection.blade_id{idx});

%% 1b. Layer 0 - Erosion Progression Cross-Check (REQ-MON-04) ---------------
% Compares this inspection against the prior one on file to catch defects
% that are spreading fast, even if today's absolute depth alone wouldn't
% trigger anything else in the pipeline. This is a monitoring/scheduling
% flag, not a pass/fail safety gate like Layers 1-2 below - a location can
% be "growing fast but still shallow" and vice versa, and both are useful
% to know separately.
previousCsvPath = fullfile(dataDir, 'erosion_inspection_data_previous.csv');
rapidThreshold_mmPerMonth = 0.5; % illustrative - tune to real coating/erosion history

progression = trackErosionProgression(inspection, previousCsvPath, ...
    'MatchTolerance_m', 3, 'RapidThreshold_mmPerMonth', rapidThreshold_mmPerMonth);

if progression.available
    fprintf('Layer 0 (Erosion Progression Cross-Check): %s - %s\n', ...
        tern(progression.anyRapid, 'FLAGGED', 'CLEAR'), progression.message);
    if progression.anyRapid
        warning('PipelineOrchestrator:RapidErosionProgression', ...
            '%.1f m span is progressing faster than %.2f mm/month. Recommend priority reinspection independent of today''s FEA/control result.', ...
            progression.worstRadialPos_m, rapidThreshold_mmPerMonth);
    end
else
    fprintf('Layer 0 (Erosion Progression Cross-Check): NO BASELINE - %s\n', progression.message);
end

%% 2. Layer 1 - Physical Feasibility Check ----------------------------------
bladeLength_m   = 120;   % nameplate blade length used for bounds checking
maxRealisticDepth_mm = 15; % beyond this the sensor reading is treated as noise/fault

feasible = verifyRequirements('feasibility', erosionMatrix, ...
    'BladeLength', bladeLength_m, 'MaxDepth', maxRealisticDepth_mm);

if ~feasible.pass
    error('PipelineOrchestrator:DataAnomaly', ...
        'Layer 1 feasibility check FAILED: %s. Halting pipeline.', feasible.message);
end
fprintf('Layer 1 (Physical Feasibility Check): PASSED - %s\n', feasible.message);

%% 3. Aerodynamic Translation ------------------------------------------------
baseLiftFactor = 1.2;
baseDragFactor = 0.045;

liftDropPerMM = 0.135;  % Cl drop per mm of pitting depth
dragGainPerMM = 0.024;  % Cd gain per mm of pitting depth

degradedLiftFactor = baseLiftFactor - (erosionMatrix(2) * liftDropPerMM);
degradedDragFactor = baseDragFactor + (erosionMatrix(2) * dragGainPerMM);

fprintf('--- Pipeline Automation Triggered ---\n');
fprintf('Baseline Cl=%.3f -> Degraded Cl=%.3f | Baseline Cd=%.3f -> Degraded Cd=%.3f\n', ...
    baseLiftFactor, degradedLiftFactor, baseDragFactor, degradedDragFactor);

%% 4. Drive the plant model for the three verification scenarios ------------
simDuration = 30;              % seconds
t = (0:0.01:simDuration)';     % 100 Hz time base

modelFile = fullfile(projectRoot, 'models', 'SimplifiedTurbineModel.slx');
useSimulink = exist(modelFile, 'file') == 4 && license('test', 'Simulink') && ~isempty(ver('Simulink'));

scenarios = struct( ...
    'name',       {'Clean',              'Unmanaged',           'Managed'}, ...
    'liftFactor', {baseLiftFactor,       degradedLiftFactor,    degradedLiftFactor}, ...
    'dragFactor', {baseDragFactor,       degradedDragFactor,    degradedDragFactor}, ...
    'damping',    {1,                    0,                     1} ...
);

results = struct();
for k = 1:numel(scenarios)
    sc = scenarios(k);

    % Bind the current scenario's variables into the base workspace so a
    % real Simulink model reads them via the block dialogs / From Workspace
    % blocks, exactly as REQ-SYS-01 requires (no manual UI editing).
    assignin('base', 'LiftCoefficient',    sc.liftFactor);
    assignin('base', 'DragCoefficient',    sc.dragFactor);
    assignin('base', 'ActiveDampingToggle', sc.damping);

    if useSimulink
        fprintf('Running Simulink scenario "%s" (damping=%d)...\n', sc.name, sc.damping);
        simOut = sim(modelFile, 'Duration', num2str(simDuration)); %#ok<*NASGU>
        bendingMoment = simOut.RotorBendingMoment; % expects a To-Workspace/logged signal
    else
        if k == 1
            fprintf(['Simulink model/license not found - running the analytic\n' ...
                     'fallback plant (localPlantModel.m) instead. See models/\n' ...
                     'build_turbine_model.m to generate the real .slx when Simulink is available.\n']);
        end
        bendingMoment = localPlantModel(t, sc.liftFactor, sc.dragFactor, sc.damping);
    end

    results.(sc.name).t = t;
    results.(sc.name).bendingMoment = bendingMoment;
    results.(sc.name).peak = max(bendingMoment);
    fprintf('  -> Scenario "%s" peak rotor bending moment: %.2f MNm\n', sc.name, results.(sc.name).peak);
end

peakClean     = results.Clean.peak;
peakUnmanaged = results.Unmanaged.peak;
peakShaftLoad = results.Managed.peak;   % the value that flows onward to ANSYS

%% 5. Layer 2 - Control Baseline Cross-Reference -----------------------------
ctrlCheck = verifyRequirements('control', [peakUnmanaged, peakShaftLoad], 'Threshold', 0.25);

fprintf('Layer 2 (Control Baseline Cross-Reference): %s - %s\n', ...
    tern(ctrlCheck.pass, 'PASSED', 'FAILED'), ctrlCheck.message);

if ~ctrlCheck.pass
    warning('PipelineOrchestrator:ControlValidationFailure', ...
        'REQ-CTRL-02 not met. Turbine flagged for emergency manual review.');
end

%% 6. Export the ANSYS boundary condition ------------------------------------
exportPath = exportAnsysBoundaryCondition(feaDir, erosionMatrix, peakShaftLoad);
fprintf('Peak shaft load (%.2f MNm) exported for ANSYS at: %s\n', peakShaftLoad, exportPath);

%% 7. Generate report figures + requirements dashboard -----------------------
reductionPct = 100 * (peakUnmanaged - peakShaftLoad) / peakUnmanaged;

generateReportPlots(results, figDir);

fprintf('\n=== PIPELINE INTEGRITY STATUS ===\n');
req1 = true; % this script itself running start-to-finish demonstrates REQ-SYS-01
req2 = ctrlCheck.pass;
% REQ-FEA-03 is only truly verified once ANSYS returns its stress result;
% here we report whether the exported load is within a sane pre-check band.
req3_precheck = peakShaftLoad < 6.0; % sanity bound before FEA confirms MPa result

fprintf('REQ-SYS-01 (Automated Workflow Execution)........ %s\n', tern(req1, 'PASSED', 'FAILED'));
fprintf('REQ-CTRL-02 (Vibration Suppression >=25%%)........ %s (Achieved %.1f%%)\n', ...
    tern(req2, 'PASSED', 'FAILED'), reductionPct);
fprintf('REQ-FEA-03 (Structural Boundary <250 MPa)........ PENDING ANSYS RUN (see /fea)\n');
fprintf('REQ-MON-04 (Erosion Progression Monitoring)...... %s\n', ...
    tern(~progression.available, 'NO BASELINE', tern(progression.anyRapid, 'FLAGGED', 'CLEAR')));
fprintf('Boundary condition file ready for import: %s\n', exportPath);
fprintf('Figures written to: %s\n', figDir);

%% 8. Build + persist + broadcast the machine-readable run summary -----------
% This is what an n8n/Zapier workflow consumes downstream - alerting on a
% failed guardrail, logging every run to a sheet, or opening a maintenance
% ticket, without anyone needing to watch the MATLAB console. See
% automation/README_automation.md for the two-minute n8n/Zapier setup.
summary = struct( ...
    'pipeline',            'blade-erosion-integrity-pipeline', ...
    'timestamp',           datestr(now, 'yyyy-mm-ddTHH:MM:SS'), ...
    'bladeId',              inspection.blade_id{idx}, ...
    'erosionRadialPos_m',   erosionMatrix(1), ...
    'erosionDepth_mm',      erosionMatrix(2), ...
    'peakClean_MNm',        peakClean, ...
    'peakUnmanaged_MNm',    peakUnmanaged, ...
    'peakManaged_MNm',      peakShaftLoad, ...
    'suppressionPct',       reductionPct, ...
    'reqSys01_pass',        req1, ...
    'reqCtrl02_pass',       req2, ...
    'reqFea03_status',      'PENDING', ...
    'reqMon04_status',      tern(~progression.available, 'NO_BASELINE', tern(progression.anyRapid, 'FLAGGED', 'CLEAR')), ...
    'worstGrowthRate_mmPerMonth', progression.worstGrowthRate_mmPerMonth, ...
    'worstGrowthRadialPos_m',     progression.worstRadialPos_m, ...
    'overallStatus',        tern(req1 && req2 && ~progression.anyRapid, 'OK', 'NEEDS_REVIEW'), ...
    'ansysBoundaryFile',    exportPath, ...
    'graphAPath',           fullfile(figDir, 'graphA_time_series_control_response.png') ...
);

summaryPath = fullfile(projectRoot, 'reports', 'pipeline_run_summary.json');
fid = fopen(summaryPath, 'w');
fprintf(fid, '%s', jsonencode(summary));
fclose(fid);
fprintf('Run summary written to: %s\n', summaryPath);

postPipelineWebhook(webhookUrl, summary);

fprintf('=== Closed-Loop Blade Erosion Pipeline: END ===\n');

% NOTE: helper functions tern() and readErosionCsv() live in their own
% files (scripts/tern.m, scripts/readErosionCsv.m) rather than as local
% functions at the end of this script. MATLAB (R2016b+) allows local
% functions in a script file, but GNU Octave 8.x does not resolve them the
% same way when the file is run directly - splitting them into their own
% files keeps this script running identically on both.
