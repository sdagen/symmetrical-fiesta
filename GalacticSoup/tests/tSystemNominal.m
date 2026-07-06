classdef (TestTags = {'system'}) tSystemNominal < matlab.unittest.TestCase
    % Nominal system-level simulation of each physical architecture model:
    % steady-state packaged throughput must land in its tolerance band and
    % the supervisor must report Nominal. These are the headline numbers
    % the trade study consumes (see docs/explainers/02).

    properties (TestParameter)
        variant = struct( ...
            'HyperCook',  struct('mdl','PhysicalHyperCook',  'bph', 308.4), ...
            'LeanBroth',  struct('mdl','PhysicalLeanBroth',  'bph', 196.8), ...
            'EverSimmer', struct('mdl','PhysicalEverSimmer', 'bph', 231.9));
    end

    methods (Test)
        function steadyRateAndMode(testCase, variant)
            in = Simulink.SimulationInput(variant.mdl);
            in = in.setModelParameter('StopTime','14400', ...
                'SaveOutput','on','SaveFormat','Dataset');
            out = sim(in);
            [flow, tele] = tSystemNominal.harvest(out);
            sel = flow.Time > 7200;
            bph = trapz(flow.Time(sel), flow.Data(sel)) / (flow.Time(end)-7200) * 3600;
            testCase.verifyEqual(bph, variant.bph, 'AbsTol', 3, ...
                sprintf('%s steady throughput drifted', variant.mdl));
            testCase.verifyEqual(double(tele.plantMode.Data(end)), 1, ...
                'plant should end a clean run in Nominal mode');
            testCase.verifyGreaterThan(mean(tele.totalPower_kW.Data), 0);
        end
    end

    methods (Static)
        function [flow, tele] = harvest(out)
            flow = []; tele = [];
            for i = 1:out.yout.numElements
                v = out.yout{i}.Values;
                if isstruct(v) && isfield(v,'flow_bps'), flow = v.flow_bps; end
                if isstruct(v) && isfield(v,'totalPower_kW'), tele = v; end
            end
            assert(~isempty(flow) && ~isempty(tele), 'root outputs missing');
        end
    end
end
