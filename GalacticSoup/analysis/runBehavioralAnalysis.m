function beh = runBehavioralAnalysis()
%RUNBEHAVIORALANALYSIS Simulate the three variant behavioral plant models
%   and extract the metrics that feed the trade study at higher fidelity
%   than the static stage-table roll-up:
%
%     SimThroughput_bph   steady-state packaged throughput, nominal run
%                         (mean over the last 2 h of a 4 h simulation)
%     TimeToFirstOut_s    cold-start time until packaged flow appears
%     Energy_kWh_per_bowl integrated actual plant power (incl. physical
%                         heater duty from the Simscape thermal network)
%                         per packaged bowl, steady-state window
%     SimRetention        worst-case single-fault throughput retention:
%                         post-fault steady rate / pre-fault steady rate
%     PeakPower_kW        maximum instantaneous plant power draw
%
%   The worst-case fault per variant is the most damaging of the modeled
%   fault points (serial single-string elements for HyperCook/LeanBroth,
%   one full production cell for IronLadle) - see docs/09 #5.
%
%   Writes behavioralMetrics.mat/.csv and docs/figures/behavioral_*.png.
%   Results are consumed by runVariantAnalysis, which overrides its static
%   throughput and N-1 retention values when this file is present.

proj = currentProject;
anaDir = char(fullfile(proj.RootFolder, 'analysis'));
figDir = char(fullfile(proj.RootFolder, 'docs', 'figures'));
if ~isfolder(figDir), mkdir(figDir); end

T_NOM   = 14400;   % nominal run length (4 h)
T_FLT   = 21600;   % fault run length (6 h)
T_FAULT = 7200;    % fault injection time
T_SS    = 7200;    % steady-state window start for nominal metrics

% {Variant, plant model, #fault inputs, worst-fault index, worst-fault label}
plants = { ...
 'HyperCook', 'BehPlantHyperCook', 6, 5, 'ConveyorNetwork (serial single-string)'; ...
 'LeanBroth', 'BehPlantLeanBroth', 4, 3, 'PrepWorkstation (serial single-string)'; ...
 'IronLadle', 'BehPlantIronLadle', 3, 1, 'ProductionCell1 (one of three cells)'};

beh = struct([]);
traces = struct([]);
for v = 1:size(plants, 1)
    mdl = plants{v,2};
    nF  = plants{v,3};

    % --- Nominal run ---
    zi = repmat(' 0', 1, nF);
    ext = sprintf('[0%s; %d%s]', zi, T_NOM, zi);
    in = Simulink.SimulationInput(mdl);
    in = in.setModelParameter('StopTime', num2str(T_NOM), 'SaveOutput','on', ...
        'SaveFormat','Dataset', 'LoadExternalInput','on', 'ExternalInput', ext);
    out = sim(in);
    flow = out.yout{1}.Values;   % packedFlow_bps
    pwr  = out.yout{3}.Values;   % totalPower_kW

    ss = flow.Time >= T_SS;
    r.Variant = plants{v,1};
    r.SimThroughput_bph = trapz(flow.Time(ss), flow.Data(ss)) ...
                          / (flow.Time(end) - T_SS) * 3600;
    firstIdx = find(flow.Data > 1e-3, 1);
    assert(~isempty(firstIdx), '%s produced no output', mdl);
    r.TimeToFirstOut_s = flow.Time(firstIdx);
    bowlsSS  = trapz(flow.Time(ss), flow.Data(ss));
    energySS = trapz(pwr.Time(pwr.Time >= T_SS), pwr.Data(pwr.Time >= T_SS)) / 3600; % kWh
    r.Energy_kWh_per_bowl = energySS / bowlsSS;
    r.MeanPower_kW = mean(pwr.Data(pwr.Time >= T_SS));
    r.PeakPower_kW = max(pwr.Data);

    % --- Worst-case single-fault run ---
    fv0 = zeros(1, nF);
    fv1 = zeros(1, nF); fv1(plants{v,4}) = 1;
    ext = sprintf('[0 %s; %d %s; %.3f %s; %d %s]', num2str(fv0), T_FAULT, ...
        num2str(fv0), T_FAULT + 0.001, num2str(fv1), T_FLT, num2str(fv1));
    in = Simulink.SimulationInput(mdl);
    in = in.setModelParameter('StopTime', num2str(T_FLT), 'SaveOutput','on', ...
        'SaveFormat','Dataset', 'LoadExternalInput','on', 'ExternalInput', ext);
    out = sim(in);
    fflow = out.yout{1}.Values;
    pre  = fflow.Time > 3600 & fflow.Time < T_FAULT;
    post = fflow.Time > T_FLT - 7200;   % settled post-fault window
    preRate  = trapz(fflow.Time(pre),  fflow.Data(pre))  / (T_FAULT - 3600) * 3600;
    postRate = trapz(fflow.Time(post), fflow.Data(post)) / 7200 * 3600;
    r.SimRetention = max(0, min(1, postRate / preRate));
    r.WorstFault = plants{v,5};

    if isempty(beh), beh = r; else, beh(end+1) = r; end %#ok<AGROW>
    traces(v).nomT = flow.Time / 3600;  traces(v).nomY = flow.Data * 3600;
    traces(v).fltT = fflow.Time / 3600; traces(v).fltY = fflow.Data * 3600;
end

save(fullfile(anaDir, 'behavioralMetrics.mat'), 'beh');
writetable(struct2table(beh), fullfile(anaDir, 'behavioralMetrics.csv'));

% ===================== Trace figures =====================
% Fixed per-variant palette (color follows the entity across all figures)
cols = [42 120 214; 27 175 122; 237 161 0] / 255;   % HC blue, LB aqua, IL yellow
surf_ = [252 252 251] / 255; inkP = [11 11 11]/255; inkS = [82 81 78]/255;
gridC = [0.88 0.88 0.87];

f = figure('Visible','off','Color',surf_,'Position',[100 100 900 400]);
ax = axes(f); hold(ax,'on');
for v = 1:3
    plot(ax, traces(v).nomT, movmean(traces(v).nomY, 25), 'Color', cols(v,:), 'LineWidth', 2);
end
yline(ax, 200, '--', 'SR-GS-002 floor (200 bph)', 'Color', [0.35 0.35 0.35], ...
    'LineWidth', 1, 'FontSize', 9, 'LabelHorizontalAlignment','left');
set(ax,'YGrid','on','GridColor',gridC,'GridAlpha',1,'Box','off','Color',surf_, ...
    'XColor',inkS,'YColor',inkS,'FontSize',10);
xlabel(ax,'Time (h)','Color',inkP); ylabel(ax,'Packaged throughput (bph, smoothed)','Color',inkP);
legend(ax, {beh.Variant}, 'Location','southeast','Box','off','TextColor',inkP);
title(ax,'Simulated cold-start and steady-state throughput (nominal)', ...
    'Color',inkP,'FontWeight','normal','FontSize',12);
exportgraphics(f, fullfile(figDir,'behavioral_throughput.png'), 'Resolution', 200);
close(f);

f = figure('Visible','off','Color',surf_,'Position',[100 100 900 400]);
ax = axes(f); hold(ax,'on');
for v = 1:3
    plot(ax, traces(v).fltT, movmean(traces(v).fltY, 25), 'Color', cols(v,:), 'LineWidth', 2);
end
xline(ax, 2, ':', 'worst-case fault injected', 'Color', [0.35 0.35 0.35], ...
    'LineWidth', 1.2, 'FontSize', 9);
yline(ax, 200, '--', 'SR floor', 'Color', [0.35 0.35 0.35], 'LineWidth', 1, 'FontSize', 9);
set(ax,'YGrid','on','GridColor',gridC,'GridAlpha',1,'Box','off','Color',surf_, ...
    'XColor',inkS,'YColor',inkS,'FontSize',10);
xlabel(ax,'Time (h)','Color',inkP); ylabel(ax,'Packaged throughput (bph, smoothed)','Color',inkP);
legend(ax, {beh.Variant}, 'Location','northeast','Box','off','TextColor',inkP);
title(ax,'Worst-case single-fault response (fault at t = 2 h)', ...
    'Color',inkP,'FontWeight','normal','FontSize',12);
exportgraphics(f, fullfile(figDir,'behavioral_fault.png'), 'Resolution', 200);
close(f);

fprintf('Behavioral analysis complete:\n');
disp(struct2table(beh));
end
