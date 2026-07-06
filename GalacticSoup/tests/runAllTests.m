function results = runAllTests(tags)
%RUNALLTESTS Run the project test suite, optionally filtered by tag.
%   results = runAllTests()            entire suite (component + analysis
%                                      + traceability + system)
%   results = runAllTests("system")    one tier only
%
%   The suite assembles from the MATLAB project's Test classification
%   labels (TestSuite.fromProject), so membership is project metadata,
%   not a hard-coded folder list. Tiers by tag:
%     component     21 unit tests of the behavioral component library
%     analysis      roll-up invariants (golden totals), formal gate
%                   verdicts, MCDA determinism
%     traceability  requirement links resolve, allocation sets complete
%     system        nominal + worst-fault simulations of the three
%                   physical architecture models (slowest tier)
%
%   A code coverage report over analysis/ and behavior/build/ lands in
%   work/coverage (derived output, not source-controlled).

import matlab.unittest.TestRunner
import matlab.unittest.plugins.CodeCoveragePlugin
import matlab.unittest.plugins.codecoverage.CoverageReport

proj = currentProject;
suite = matlab.unittest.TestSuite.fromProject(proj);
if nargin > 0 && ~isempty(tags)
    suite = suite.selectIf(matlab.unittest.selectors.HasTag(char(tags)));
end
fprintf('suite: %d tests\n', numel(suite));

runner = TestRunner.withTextOutput('OutputDetail', 1);
covDir = fullfile(char(proj.RootFolder), 'work', 'coverage');
if ~isfolder(covDir), mkdir(covDir); end
runner.addPlugin(CodeCoveragePlugin.forFolder( ...
    {char(fullfile(proj.RootFolder,'analysis')), ...
     char(fullfile(proj.RootFolder,'behavior','build'))}, ...
    'Producing', CoverageReport(covDir)));

results = runner.run(suite);
disp(table(results));
assertSuccess(results);
fprintf('coverage report: %s\n', fullfile(covDir, 'index.html'));
end
