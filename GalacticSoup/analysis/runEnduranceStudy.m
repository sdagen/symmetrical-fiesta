function endr = runEnduranceStudy()
%RUNENDURANCESTUDY Ingredient-storage endurance vs SR-GS-021 (72 hours).
%   Fills every ingredient store to capacity, cuts resupply at t = 3600 s
%   (Resupply_Cutoff_T override), and measures how long each architecture
%   keeps producing: endurance = last productive instant minus cutoff.
%   The requirement asks for 72 hours of stored ingredients at nominal
%   production rate; the stereotype-sized stores hold a few hours. This
%   study turns that suspicion into a measured, baselined finding, and
%   prices what compliance would cost against the mass budget.
%
%   Produces enduranceResults.mat / enduranceSummary.csv.

CUTOFF = 3600; T_STOP = 46800;   % 12 h of post-cutoff observation

proj = currentProject;
anaDir = char(fullfile(proj.RootFolder, 'analysis'));
M = load(fullfile(anaDir, 'variantMetrics.mat'));

% {variant, model, init var, cap bowls, nominal bph}
models = {'HyperCook','PhysicalHyperCook','HC_StorageInit_bowls',2000,308.4; ...
          'LeanBroth','PhysicalLeanBroth','LB_StorageInit_bowls',800,196.8; ...
          'EverSimmer','PhysicalEverSimmer','ES_StorageInit_bowls',1200,231.9};
nV = size(models,1);

clear in
for v = 1:nV
    s = Simulink.SimulationInput(models{v,2});
    s = s.setModelParameter('StopTime', num2str(T_STOP), ...
        'SaveOutput','on', 'SaveFormat','Dataset');
    s = s.setVariable('Resupply_Cutoff_T', CUTOFF, 'Workspace', models{v,2});
    s = s.setVariable(models{v,3}, models{v,4}, 'Workspace', models{v,2});
    in(v) = s; %#ok<AGROW>
end
% three different models: run serially (parsim needs one model per array)
endurance_h = zeros(nV,1); bowlsAfter = zeros(nV,1);
for v = 1:nV
    out = sim(in(v));
    flow = [];
    for i = 1:out.yout.numElements
        y = out.yout{i}.Values;
        if isstruct(y) && isfield(y,'flow_bps'), flow = y.flow_bps; end
    end
    % endurance = LAST productive instant (bursty batch output has gaps;
    % a first-dip detector reads a batch gap as starvation)
    lastIdx = find(flow.Data*3600 > 20, 1, 'last');
    endurance_h(v) = (flow.Time(lastIdx) - CUTOFF) / 3600;
    post = flow.Time > CUTOFF;
    bowlsAfter(v) = trapz(flow.Time(post), flow.Data(post));
    fprintf('%s: %.2f h endurance, %.0f bowls after cutoff\n', ...
        models{v,1}, endurance_h(v), bowlsAfter(v));
end

% price of compliance: 72 h at nominal rate, in bowls and in mass, vs budget
req_h = 72;
reqBowls = req_h * [models{v,3}]; %#ok<NASGU>
reqBowls = req_h * cell2mat(models(:,5));
reqMass_kg = reqBowls * 0.55;                     % Bowl_kg
massUsed = [M.results.Mass_kg]';                  % rolled-up system mass
massBudget = M.caps.Mass_kg;

endr.variants = models(:,1)';
endr.storageCap_bowls = cell2mat(models(:,4));
endr.endurance_h = endurance_h';
endr.bowlsAfterCutoff = bowlsAfter';
endr.required_h = req_h;
endr.requiredStorage_bowls = reqBowls';
endr.requiredStorageMass_kg = reqMass_kg';
endr.systemMass_kg = massUsed';
endr.massBudget_kg = massBudget;
save(fullfile(anaDir, 'enduranceResults.mat'), 'endr');
T = table(models(:,1), endurance_h, cell2mat(models(:,4)), reqBowls, reqMass_kg, ...
    'VariableNames', {'Variant','Endurance_h','StorageCap_bowls', ...
    'Required_bowls','RequiredMass_kg'});
writetable(T, fullfile(anaDir, 'enduranceSummary.csv'));

fprintf(['\nSR-GS-021 asks for %d h; measured endurance %.1f / %.1f / %.1f h.\n' ...
    'Compliant storage would hold %.0f-%.0f bowls = %.0f-%.0f kg of\n' ...
    'ingredients against a %.0f kg TOTAL system mass budget.\n'], ...
    req_h, endurance_h, min(reqBowls), max(reqBowls), ...
    min(reqMass_kg), max(reqMass_kg), massBudget);
end
