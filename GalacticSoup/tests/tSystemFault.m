classdef (TestTags = {'system'}) tSystemFault < matlab.unittest.TestCase
    % Worst-case single-fault response per variant (SR-GS-026 story):
    % single-string variants collapse to zero, EverSimmer retains ~2/3 and
    % its supervisor reports Degraded. Faults inject via the Fault_T_*
    % model-workspace step gates at t = 7200 s.

    properties (TestParameter)
        variant = struct( ...
            'HyperCook',  struct('mdl','PhysicalHyperCook',  'fvar','Fault_T_QC',    'ret',0,     'mode',[]), ...
            'LeanBroth',  struct('mdl','PhysicalLeanBroth',  'fvar','Fault_T_Prep',  'ret',0,     'mode',[]), ...
            'EverSimmer', struct('mdl','PhysicalEverSimmer', 'fvar','Fault_T_Cell1', 'ret',0.672, 'mode',2));
    end

    methods (Test)
        function worstFaultRetention(testCase, variant)
            in = Simulink.SimulationInput(variant.mdl);
            in = in.setModelParameter('StopTime','21600', ...
                'SaveOutput','on','SaveFormat','Dataset');
            in = in.setVariable(variant.fvar, 7200, 'Workspace', variant.mdl);
            out = sim(in);
            [flow, tele] = tSystemNominal.harvest(out);
            pre  = flow.Time > 3600  & flow.Time < 7200;
            post = flow.Time > 14400;
            preRate  = trapz(flow.Time(pre),  flow.Data(pre))  / 3600;
            postRate = trapz(flow.Time(post), flow.Data(post)) / 7200;
            retention = postRate / preRate;
            testCase.verifyEqual(retention, variant.ret, 'AbsTol', 0.02, ...
                sprintf('%s worst-fault retention drifted', variant.mdl));
            if ~isempty(variant.mode)
                testCase.verifyEqual(double(tele.plantMode.Data(end)), variant.mode, ...
                    'supervisor should flag the degradation');
            end
        end
    end
end
