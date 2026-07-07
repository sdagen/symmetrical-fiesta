classdef (TestTags = {'analysis'}) tTradeDeterminism < sltest.TestCase
    % The MCDA is seeded (rng(42)): two runs over the same metrics must be
    % bit-identical, and the current expected outcome is baselined so silent
    % drift in criteria or weights cannot pass unnoticed.

    methods (Test)
        function reproducible(testCase)
            compliant = {'HyperCook','EverSimmer'};
            t1 = runTradeStudy(compliant);
            t2 = runTradeStudy(compliant);
            testCase.verifyEqual(t1.scores, t2.scores);
            testCase.verifyEqual(t1.winShare, t2.winShare);
        end

        function expectedOutcome(testCase)
            t = runTradeStudy({'HyperCook','EverSimmer'});
            es = strcmp(t.variants, 'EverSimmer');
            testCase.verifyEqual(t.winShare(es), 0.9842, 'AbsTol', 1e-12, ...
                'seeded Monte Carlo win share is deterministic');
            scen = fieldnames(t.scenarios);
            for s = 1:numel(scen)
                [~, w] = max(t.scores(:, s));
                testCase.verifyTrue(es(w), ...
                    sprintf('EverSimmer should win scenario %s', scen{s}));
            end
        end
    end
end
