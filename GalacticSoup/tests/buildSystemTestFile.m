function buildSystemTestFile()
%BUILDSYSTEMTESTFILE Generate the Simulink Test system-tier test file.
%   Creates tests/GalacticSoupSystemTests.mldatx (ADR-022): two suites of
%   simulation test cases on the three physical architecture models.
%
%   Nominal suite - steady throughput and plant mode via custom criteria:
%     HC/ES cases verify the SR-GS-002 floor AND record the regression baseline,
%     and carry Verify links to SR-GS-002 so verification status rolls up
%     in the Requirements Editor (the capability MATLAB Test lacks).
%     The LB case is a regression baseline only (196.8 bph band) - LeanBroth
%     genuinely fails the floor, and that story belongs to the compliance
%     gate, not to a Verify link that would assert the opposite.
%   WorstFault suite - Fault_T_* parameter overrides at t = 7200 s:
%     ES verifies SR-GS-026 (retention ~2/3, Degraded mode) with a Verify
%     link; HC/LB baseline their 0% collapse as unlinked regression cases.
%
%   Destructive and idempotent: recreates the file and re-links, purging
%   stale Verify links to this artifact from the requirement set first.

proj = currentProject;
tdir = char(fullfile(proj.RootFolder, 'tests'));
tfPath = fullfile(tdir, 'GalacticSoupSystemTests.mldatx');

sltest.testmanager.clear;
sltest.testmanager.clearResults;
slreq.clear();
srSet = slreq.load(fullfile(char(proj.RootFolder), 'requirements', 'SystemRequirements.slreqx'));

% purge stale Verify links from earlier builds of this artifact
for id = {'SR-GS-002','SR-GS-026'}
    sr = find(srSet, 'Id', id{1});
    for L = inLinks(sr)
        try
            s = source(L);
            if contains(char(s.artifact), 'GalacticSoupSystemTests')
                remove(L);
            end
        catch
        end
    end
end
if isfile(tfPath), delete(tfPath); end

tf = sltest.testmanager.TestFile(tfPath);
suites = getTestSuites(tf);
suites(1).Name = 'Nominal';
% every new suite ships a default placeholder case - drop it
for stray = getTestCases(suites(1))
    remove(stray);
end
faultSuite = createTestSuite(tf, 'WorstFault');
% createTestSuite ships a default placeholder case - drop it
for stray = getTestCases(faultSuite)
    remove(stray);
end

% {name, model, steady bph, verifyFloor, linkReq}
nom = { ...
 'HyperCook nominal',  'PhysicalHyperCook',  308.4, true,  'SR-GS-002'; ...
 'LeanBroth nominal - regression baseline', 'PhysicalLeanBroth', 196.8, false, ''; ...
 'EverSimmer nominal', 'PhysicalEverSimmer', 231.9, true,  'SR-GS-002'};
for i = 1:size(nom,1)
    tc = createTestCase(suites(1), 'simulation', nom{i,1});
    setProperty(tc, 'Model', nom{i,2});
    setProperty(tc, 'OverrideStopTime', true);
    setProperty(tc, 'StopTime', 14400);
    floorCheck = '';
    if nom{i,4}
        floorCheck = sprintf('test.verifyGreaterThanOrEqual(bph, 200, ''SR-GS-002 floor'');%s', newline);
    end
    cc = getCustomCriteria(tc);
    cc.Enabled = true;
    cc.Callback = sprintf([ ...
        'yout = test.sltest_simout.get(''yout'');\n' ...
        'flow = []; tele = [];\n' ...
        'for i = 1:yout.numElements\n' ...
        '    v = yout{i}.Values;\n' ...
        '    if isstruct(v) && isfield(v,''flow_bps''), flow = v.flow_bps; end\n' ...
        '    if isstruct(v) && isfield(v,''totalPower_kW''), tele = v; end\n' ...
        'end\n' ...
        'sel = flow.Time > 7200;\n' ...
        'bph = trapz(flow.Time(sel), flow.Data(sel))/(flow.Time(end)-7200)*3600;\n' ...
        '%s' ...
        'test.verifyEqual(bph, %g, ''AbsTol'', 3, ''regression band'');\n' ...
        'test.verifyEqual(double(tele.plantMode.Data(end)), 1, ''Nominal mode'');\n'], ...
        floorCheck, nom{i,3});
end

% {name, model, fault var, retention, endMode(if checked), linkReq}
flt = { ...
 'HyperCook worst fault - regression baseline', 'PhysicalHyperCook', 'Fault_T_QC',    0,     [], ''; ...
 'LeanBroth worst fault - regression baseline', 'PhysicalLeanBroth', 'Fault_T_Prep',  0,     [], ''; ...
 'EverSimmer worst fault',                 'PhysicalEverSimmer','Fault_T_Cell1', 0.672,  2, 'SR-GS-026'};
for i = 1:size(flt,1)
    tc = createTestCase(faultSuite, 'simulation', flt{i,1});
    setProperty(tc, 'Model', flt{i,2});
    setProperty(tc, 'OverrideStopTime', true);
    setProperty(tc, 'StopTime', 21600);
    ps = addParameterSet(tc, 'Name', 'worstFault');
    addParameterOverride(ps, flt{i,3}, 7200);
    modeCheck = '';
    if ~isempty(flt{i,5})
        modeCheck = sprintf('test.verifyEqual(double(tele.plantMode.Data(end)), %d, ''Degraded mode'');%s', flt{i,5}, newline);
    end
    cc = getCustomCriteria(tc);
    cc.Enabled = true;
    cc.Callback = sprintf([ ...
        'yout = test.sltest_simout.get(''yout'');\n' ...
        'flow = []; tele = [];\n' ...
        'for i = 1:yout.numElements\n' ...
        '    v = yout{i}.Values;\n' ...
        '    if isstruct(v) && isfield(v,''flow_bps''), flow = v.flow_bps; end\n' ...
        '    if isstruct(v) && isfield(v,''totalPower_kW''), tele = v; end\n' ...
        'end\n' ...
        'pre  = flow.Time > 3600  & flow.Time < 7200;\n' ...
        'post = flow.Time > 14400;\n' ...
        'preR  = trapz(flow.Time(pre),  flow.Data(pre))/3600;\n' ...
        'postR = trapz(flow.Time(post), flow.Data(post))/7200;\n' ...
        'retention = postR/preR;\n' ...
        '%s' ...
        'test.verifyEqual(retention, %g, ''AbsTol'', 0.02, ''worst-fault retention'');\n'], ...
        modeCheck, flt{i,4});
end

% save FIRST so cases carry persistent IDs, then link (links made against
% unsaved cases capture provisional IDs and never match executed results)
saveToFile(tf);
linkSpec = [nom(:,[1 5]); flt(:,[1 6])];
for s = getTestSuites(tf)
    for tc = getTestCases(s)
        k = strcmp(linkSpec(:,1), tc.Name);
        if any(k) && ~isempty(linkSpec{k,2})
            lnk = slreq.createLink(tc, find(srSet, 'Id', linkSpec{k,2})); %#ok<NASGU>
        end
    end
end
saveToFile(tf);
slreq.saveAll();
pf = {proj.Files.Path};
if ~any(strcmpi(pf, tfPath)), addFile(proj, tfPath); end
fprintf('%s built: 6 cases, 3 Verify links\n', tfPath);
end
