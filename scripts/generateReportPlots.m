function generateReportPlots(results, figDir)
%GENERATEREPORTPLOTS Render Graph A (rotor bending moment time-series,
%   Clean vs Unmanaged vs Managed) from the pipeline's simulation output
%   and save it as a PNG for embedding in README.md.
%
%   results.Clean/.Unmanaged/.Managed each have fields .t and .bendingMoment

    if ~exist(figDir, 'dir'); mkdir(figDir); end

    fig = figure('Visible', 'off', 'Position', [100 100 1300 700], 'Color', 'w');
    hold on;

    hUnmanaged = plot(results.Unmanaged.t, results.Unmanaged.bendingMoment, ...
        'Color', [0.84 0.27 0.27], 'LineWidth', 1.2);
    hManaged = plot(results.Managed.t, results.Managed.bendingMoment, ...
        'Color', [0.18 0.49 0.24], 'LineWidth', 1.6);
    hClean = plot(results.Clean.t, results.Clean.bendingMoment, ...
        'Color', [0.25 0.44 0.69], 'LineWidth', 1.6);

    % Horizontal reference lines at each scenario's peak. Uses plot() of a
    % 2-point line rather than yline() - yline is MATLAB-only (R2018b+)
    % and not implemented in GNU Octave.
    xLimGuess = [min(results.Clean.t), max(results.Clean.t)];
    plot(xLimGuess, [1 1]*results.Unmanaged.peak, ':', 'Color', [0.84 0.27 0.27]);
    plot(xLimGuess, [1 1]*results.Managed.peak,   ':', 'Color', [0.18 0.49 0.24]);
    plot(xLimGuess, [1 1]*results.Clean.peak,     ':', 'Color', [0.25 0.44 0.69]);

    xlabel('Time (s)');
    ylabel('Rotor Bending Moment (MNm)');
    % Single-line title (not a multi-line cell array) and no '~' characters
    % in any plotted string below - GNU Octave's gnuplot backend treats
    % both a cell-array title's bold styling and '~' as text-formatting
    % escapes ("enhanced" mode overstrike syntax), which garbles the text.
    % MATLAB doesn't have this issue, but avoiding both keeps the figure
    % rendering identically on either platform.
    title('Rotor Shaft Bending Moment Over Time - 30 s Simulation Run (Clean vs. Unmanaged vs. Active Damped)');
    legend([hUnmanaged, hManaged, hClean], { ...
        sprintf('Unmanaged Erosion - Peak %.2f MNm (Resonance Breach)', results.Unmanaged.peak), ...
        sprintf('Active Damped Controller - Settles approx %.2f MNm', results.Managed.peak), ...
        sprintf('Clean Blade Baseline - approx %.2f MNm', results.Clean.peak) ...
        }, 'Location', 'northeast', 'FontSize', 8);
    grid on;
    box on;
    xlim([0, max(results.Clean.t)]);

    outPath = fullfile(figDir, 'graphA_time_series_control_response.png');
    % print()/-dpng is used instead of exportgraphics() (MATLAB R2020a+
    % only, not implemented in GNU Octave) for broad version compatibility.
    print(fig, outPath, '-dpng', '-r150');
    close(fig);

    fprintf('Graph A written to: %s\n', outPath);
    fprintf(['Graph B (ANSYS stress contour) is produced from the FEA run itself: \n' ...
             '  run/inspect fea/boundary_condition.mac in ANSYS Mechanical, then\n' ...
             '  export the equivalent-stress contour screenshot into reports/figures/\n' ...
             '  as graphB_ansys_stress_contour.png (see fea/README_fea.md).\n']);
end
