function results = runAllTests(tags)
%RUNALLTESTS Run the project's full verification stack.
%   results = runAllTests()            everything: the MATLAB-based tiers
%                                      (component/analysis/traceability)
%                                      plus the Simulink Test system tier
%                                      (GalacticSoupSystemTests.mldatx)
%                                      with its requirement Verify links
%   results = runAllTests("analysis")  one MATLAB tier only (skips the
%                                      Simulink Test file)
%
%   MATLAB tiers: sltest.TestCase classes (Test-Manager compatible),
%   assembled from the project's Test classification labels, run with a
%   coverage report over analysis/ and behavior/build/ (work/coverage).
%   System tier: simulation test cases on the three architecture models,
%   run through the Simulink Test Manager; after the run the requirement
%   verification status is refreshed and reported (SR-GS-002, SR-GS-026).

import matlab.unittest.TestRunner
import matlab.unittest.plugins.CodeCoveragePlugin
import matlab.unittest.plugins.codecoverage.CoverageReport

proj = currentProject;
suite = matlab.unittest.TestSuite.fromProject(proj);
% fromProject also adapts .mldatx cases; the system tier runs once,
% explicitly, through the Simulink Test Manager below (that path is what
% registers results for requirement verification status)
suite = suite(~contains({suite.Name}, 'GalacticSoupSystemTests'));
if nargin > 0 && ~isempty(tags)
    suite = suite.selectIf(matlab.unittest.selectors.HasTag(char(tags)));
end
fprintf('MATLAB tiers: %d tests\n', numel(suite));

runner = TestRunner.withTextOutput('OutputDetail', 1);
covDir = fullfile(char(proj.RootFolder), 'work', 'coverage');
if ~isfolder(covDir), mkdir(covDir); end
runner.addPlugin(CodeCoveragePlugin.forFolder( ...
    {char(fullfile(proj.RootFolder,'analysis')), ...
     char(fullfile(proj.RootFolder,'behavior','build'))}, ...
    'Producing', CoverageReport(covDir)));
results = runner.run(suite);
assertSuccess(results);

if nargin > 0 && ~isempty(tags)
    return   % tier-filtered run: MATLAB tiers only
end

% --- Simulink Test system tier ---
bdclose('all');
sltest.testmanager.clearResults;
sltest.testmanager.load( ...
    fullfile(char(proj.RootFolder),'tests','GalacticSoupSystemTests.mldatx'));
rs = sltest.testmanager.run;
nPass = 0; nTot = 0;
for s = getTestSuiteResults(getTestFileResults(rs))
    for r = getTestCaseResults(s)
        nTot = nTot + 1;
        nPass = nPass + (r.Outcome == sltest.testmanager.TestResultOutcomes.Passed);
    end
end
fprintf('system tier (Simulink Test): %d/%d cases pass\n', nPass, nTot);
assert(nPass == nTot, 'Simulink Test system tier has failures');

% requirement verification rollup (fresh set state, then update)
slreq.clear();
srSet = slreq.load(fullfile(char(proj.RootFolder),'requirements','SystemRequirements.slreqx'));
updateVerificationStatus(srSet);
for id = {'SR-GS-002','SR-GS-026'}
    st = getVerificationStatus(find(srSet, 'Id', id{1}));
    fprintf('%s verification: %d passed, %d failed, %d unexecuted\n', ...
        id{1}, st.passed, st.failed, st.unexecuted);
    assert(st.failed == 0 && st.unexecuted == 0, '%s not verified', id{1});
end
fprintf('coverage report: %s\n', fullfile(covDir, 'index.html'));
end
