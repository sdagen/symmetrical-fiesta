classdef (TestTags = {'traceability'}) tTraceability < sltest.TestCase
    % Traceability integrity: every requirement link resolves to a live
    % architecture element, and the allocation sets carry their full
    % complement. These are the artifacts that silently rot during
    % structural rework (see ADR-019/ADR-020 war stories).

    properties (TestParameter)
        % counts include the 4 root-architecture links per model for the
        % emergent budget SRs, SR-GS-011..014 (ADR-024). Link TYPE is
        % baseline-scoped (ADR-035): only the adopted baseline
        % (EverSimmer, ADR-009) carries Implement links; the rejected
        % variants' links are all Relate, so they keep their trade-study
        % traceability without contributing to implementation status.
        linkSet = struct( ...
            'HyperCook',  struct('mdl','PhysicalHyperCook',  'n',14, 'baseline',false), ...
            'LeanBroth',  struct('mdl','PhysicalLeanBroth',  'n',14, 'baseline',false), ...
            'EverSimmer', struct('mdl','PhysicalEverSimmer', 'n',20, 'baseline',true));
    end

    methods (TestClassSetup)
        function closeGateModel(~)
            % the gate model's embedded requirement set blocks slreq.clear
            if bdIsLoaded('GalacticSoupComplianceGate')
                close_system('GalacticSoupComplianceGate', 0);
            end
        end
    end

    methods (Test)
        function linksResolve(testCase, linkSet)
            slreq.clear();
            load_system(linkSet.mdl);
            ls = slreq.load(linkSet.mdl);
            links = getLinks(ls);
            testCase.verifyNumElements(links, linkSet.n, ...
                sprintf('%s link inventory changed', linkSet.mdl));
            for L = links
                src = slreq.structToObj(source(L));
                q = src.getQualifiedName();
                testCase.verifyTrue(startsWith(q, linkSet.mdl), ...
                    sprintf('link source outside model: %s', q));
                dst = slreq.structToObj(destination(L));
                testCase.verifyMatches(dst.Id, '^SR-GS-\d+$');
            end
            types = arrayfun(@(L) string(L.Type), links);
            if linkSet.baseline
                testCase.verifyTrue(all(types == "Implement"), ...
                    'baseline variant must carry Implement links (ADR-035)');
            else
                testCase.verifyTrue(all(types == "Relate"), sprintf( ...
                    '%s is a rejected alternate: links must be Relate, not Implement (ADR-035)', ...
                    linkSet.mdl));
            end
        end

        function allocationSets(testCase)
            as = systemcomposer.allocation.load('LogicalToEverSimmer');
            testCase.verifyNumElements(as.Scenarios(1).Allocations, 24);
            testCase.verifyEqual(as.Scenarios(1).Name, 'VariantC');
            for nm = {'LogicalToHyperCook','LogicalToLeanBroth','FuncToLogical'}
                a2 = systemcomposer.allocation.load(nm{1});
                testCase.verifyGreaterThan(numel(a2.Scenarios(1).Allocations), 0, nm{1});
            end
        end
    end
end
