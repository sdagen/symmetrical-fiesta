classdef (TestTags = {'analysis'}) tGateAgreement < sltest.TestCase
    % The formal Requirements Table gate and the expected verdicts.
    % runComplianceGate hard-asserts formal-vs-procedural agreement
    % internally; this test pins the expected verdict pattern on top:
    % everything passes except LeanBroth throughput.

    methods (Test)
        function gateVerdicts(testCase)
            gate = runComplianceGate();
            testCase.verifySize(gate{:,1:8}, [3 8]);
            testCase.verifyEqual(nnz(gate{:,1:8}), 23, ...
                'expected exactly 23 of 24 gate checks to pass');
            lb = gate({'LeanBroth'},:);
            testCase.verifyFalse(lb.Throughput, ...
                'LeanBroth must fail the throughput gate at behavioral fidelity');
            testCase.verifyTrue(all(gate{'HyperCook',1:8}));
            testCase.verifyTrue(all(gate{'EverSimmer',1:8}));
            testCase.verifyEqual(gate.AllGatesPass, [true; false; true]);
        end
    end
end
