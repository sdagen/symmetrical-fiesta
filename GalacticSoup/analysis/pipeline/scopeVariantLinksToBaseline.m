function scopeVariantLinksToBaseline()
%SCOPEVARIANTLINKSTOBASELINE Retype non-baseline variants' Implement links.
%   ADR-035: requirement implementation/verification status is reported
%   against the adopted baseline architecture (EverSimmer, ADR-009).
%   Requirements Toolbox rolls implementation status up over ALL loaded
%   Implement links, so the two non-selected variants' Implement links
%   made every report claim coverage from three mutually exclusive
%   architectures at once. This retypes each Implement link whose source
%   lives in PhysicalHyperCook or PhysicalLeanBroth to 'Relate'
%   ("Related to"): the trade-study traceability stays visible in the
%   Requirements Editor and the generated report, but contributes nothing
%   to implementation status. EverSimmer's and the functional
%   architecture's Implement links are untouched.
%
%   Idempotent: a second run finds no Implement links to retype.

alternates = {'PhysicalHyperCook', 'PhysicalLeanBroth'};

slreq.clear();
for m = 1:numel(alternates)
    mdl = alternates{m};
    load_system(mdl);
    ls = slreq.load(mdl);
    nRetyped = 0;
    for L = getLinks(ls)
        if strcmp(L.Type, 'Implement')
            L.Type = 'Relate';
            nRetyped = nRetyped + 1;
        end
    end
    fprintf('%s: %d Implement link(s) retyped to Relate\n', mdl, nRetyped);
end
slreq.saveAll();
end
