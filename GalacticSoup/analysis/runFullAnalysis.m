function [results, gate, trade] = runFullAnalysis()
%RUNFULLANALYSIS End-to-end variant analysis chain with formal gating.
%   1. runVariantAnalysis  - roll up metrics per variant (procedural flags)
%   2. runComplianceGate   - formal verification via the Requirements Table
%                            gate model; hard-errors on any disagreement
%                            with the procedural flags
%   3. runTradeStudy       - MCDA scoring; only runs if every variant that
%                            enters scoring passed the formal gate
%
%   The trade study intentionally sits downstream of the formal gate: a
%   variant that fails formal compliance has no business being scored.

results = runVariantAnalysis();
gate = runComplianceGate();

nonCompliant = gate.Properties.RowNames(~gate.AllGatesPass);
if ~isempty(nonCompliant)
    error('gs:gateFailed', ...
        'Formal compliance gate failed for: %s. Trade study not run.', ...
        strjoin(nonCompliant, ', '));
end

trade = runTradeStudy();
end
