classdef (TestTags = {'analysis'}) tEndurance < sltest.TestCase
    % Storage-endurance conclusions (ADR-030): regression baselines for
    % the SR-GS-021 FINDING. Every variant fails the 72-hour requirement
    % by an order of magnitude, and pricing compliance exposes a
    % requirements conflict: 72 h of ingredients at nominal rate masses
    % 7.8-12.2 t against the 15 t total system mass budget (SR-GS-011).
    % These tests keep the finding honest until the requirements owner
    % resolves the conflict - if a redesign ever fixes endurance, the
    % baselines fail and force a conscious update.

    methods (Test)
        function enduranceBaselines(tc)
            S = load(fullfile(char(currentProject().RootFolder), ...
                'analysis', 'enduranceResults.mat'));
            e = S.endr;
            tc.verifyEqual(e.variants, {'HyperCook','LeanBroth','EverSimmer'});
            tc.verifyEqual(e.endurance_h, [6.41 4.66 5.44], 'AbsTol', 0.3, ...
                'measured endurance moved off its baselines');
            tc.verifyTrue(all(e.endurance_h < e.required_h), ...
                'a variant now meets SR-GS-021 - retire the finding consciously');
        end

        function complianceCostExceedsHalfMassBudget(tc)
            % the requirements-conflict core: 72 h of stored ingredients
            % masses more than half the TOTAL system budget for every
            % variant (and 81% of it for HyperCook)
            S = load(fullfile(char(currentProject().RootFolder), ...
                'analysis', 'enduranceResults.mat'));
            e = S.endr;
            tc.verifyEqual(e.requiredStorageMass_kg, ...
                72 * [308.4 196.8 231.9] * 0.55, 'RelTol', 1e-6);
            tc.verifyTrue(all(e.requiredStorageMass_kg > 0.5 * e.massBudget_kg), ...
                'the SR-GS-021 vs SR-GS-011 conflict has softened - update ADR-030');
        end
    end
end
