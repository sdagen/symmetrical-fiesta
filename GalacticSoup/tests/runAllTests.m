function results = runAllTests(tier)
%RUNALLTESTS Run the project's complete verification stack as ONE suite.
%   results = runAllTests()          all 37 tests: MATLAB-based tiers
%                                    (component/analysis/traceability)
%                                    and the Simulink Test simulation
%                                    cases, one runner, equal citizens
%   results = runAllTests("analysis")     one MATLAB tier by tag
%   results = runAllTests("system")       just the simulation cases
%
%   The suite assembles from project metadata: MATLAB test classes carry
%   the Test classification label, and TestSuite.fromProject also adapts
%   the Simulink Test file's cases into the same suite, so both kinds run
%   through the same matlab.unittest runner, appear in the same results
%   table, and register their outcomes identically - including for
%   requirement verification: after a full run the SR verification status
%   is refreshed and asserted (SR-GS-002, SR-GS-026 verified by the
%   simulation cases' Verify links).
%
%   A coverage report over analysis/ and behavior/build/ lands in
%   work/coverage (derived output, not source-controlled).

import matlab.unittest.TestRunner
import matlab.unittest.plugins.CodeCoveragePlugin
import matlab.unittest.plugins.codecoverage.CoverageReport

proj = currentProject;
suite = matlab.unittest.TestSuite.fromProject(proj);
isSim = contains({suite.Name}, 'GalacticSoupSystemTests');
fullRun = nargin == 0 || isempty(tier);
if ~fullRun
    if strcmpi(char(tier), 'system')
        suite = suite(isSim);   % simulation cases carry no TestTags
    else
        suite = suite.selectIf(matlab.unittest.selectors.HasTag(char(tier)));
    end
end
fprintf('suite: %d tests (%d simulation cases)\n', numel(suite), ...
    nnz(contains({suite.Name}, 'GalacticSoupSystemTests')));

runner = TestRunner.withTextOutput('OutputDetail', 1);
covDir = fullfile(char(proj.RootFolder), 'work', 'coverage');
if ~isfolder(covDir), mkdir(covDir); end
runner.addPlugin(CodeCoveragePlugin.forFolder( ...
    {char(fullfile(proj.RootFolder,'analysis')), ...
     char(fullfile(proj.RootFolder,'behavior','build'))}, ...
    'Producing', CoverageReport(covDir)));

bdclose('all');
sltest.testmanager.clearResults;
results = runner.run(suite);
disp(table(results));
assertSuccess(results);

if fullRun
    % requirement verification rollup: fresh set state, then update
    slreq.clear();
    srSet = slreq.load(fullfile(char(proj.RootFolder), ...
        'requirements','SystemRequirements.slreqx'));
    updateVerificationStatus(srSet);
    for id = {'SR-GS-002','SR-GS-026'}
        st = getVerificationStatus(find(srSet, 'Id', id{1}));
        fprintf('%s verification: %d passed, %d failed, %d unexecuted\n', ...
            id{1}, st.passed, st.failed, st.unexecuted);
        assert(st.failed == 0 && st.unexecuted == 0, '%s not verified', id{1});
    end
end
fprintf('coverage report: %s\n', fullfile(covDir, 'index.html'));
end
