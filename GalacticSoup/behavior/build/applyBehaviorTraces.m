function applyBehaviorTraces()
%APPLYBEHAVIORTRACES Trace architecture components to behavioral models.
%   Adds the BehaviorRealization stereotype (BehaviorModel,
%   IntegrationLevel) to GalacticSoupProfile and applies it to every
%   production-path component of the three physical variant models plus
%   their root architectures, recording which behavioral model realizes
%   each component and how it is integrated:
%
%     linked-behavior    Simulink behavior linked into the component
%                        (LeanBroth kettles via BehKettleBehavior)
%     plant-composition  behavior exercised through the variant plant
%                        model (BehPlant*), the analysis vehicle
%
%   Idempotent: re-applying updates property values in place.

profName = 'GalacticSoupProfile';
prof = systemcomposer.profile.Profile.find(profName);
if isempty(prof)
    prof = systemcomposer.profile.Profile.load(profName);
end
% getStereotype errors (rather than returning empty) when absent
try
    prof.getStereotype('BehaviorRealization');
    hasStereo = true;
catch
    hasStereo = false;
end
if ~hasStereo
    st = prof.addStereotype('BehaviorRealization');
    st.addProperty('BehaviorModel', 'Type', 'string');
    st.addProperty('IntegrationLevel', 'Type', 'string');
    prof.save();
    fprintf('Stereotype %s.BehaviorRealization added\n', profName);
end
stq = [profName '.BehaviorRealization'];

% {model, {component path (relative), behavior model, integration level}}
PLANT = 'plant-composition';
maps = { ...
 'PhysicalHyperCook', { ...
   'RoboticPrepLine1','BehPrepUnit',PLANT; 'RoboticPrepLine2','BehPrepUnit',PLANT; ...
   'ContinuousCookLine1','BehCookLine',PLANT; 'ContinuousCookLine2','BehCookLine',PLANT; ...
   'ContinuousCookLine3','BehCookLine',PLANT; 'ContinuousCookLine4','BehCookLine',PLANT; ...
   'InlineQCScanner','BehQCStation',PLANT; 'HighSpeedPackagingLine','BehPackager',PLANT; ...
   'ColdStorageVault','BehStorage',PLANT; 'AmbientStorageSilo','BehStorage',PLANT; ...
   'ConveyorNetwork','SubTransport',PLANT; 'CentralControlComputer','BehSupervisor',PLANT}; ...
 'PhysicalLeanBroth', { ...
   'PrepWorkstation','BehPrepUnit',PLANT; ...
   ... % Kettles: BehKettleBehavior (buildKettleAdapters) is the verified
   ... % port-preserving link, but the committed architecture keeps the
   ... % kettles UNLINKED because linking drops the component's stereotype
   ... % property values from the roll-up (ADR-017)
   'BatchKettle1','BehKettleBehavior','adapter-available'; ...
   'BatchKettle2','BehKettleBehavior','adapter-available'; ...
   'QCBench','BehQCStation',PLANT; 'SemiAutoPackager','BehPackager',PLANT; ...
   'ColdStoreLocker','BehStorage',PLANT; 'DryGoodsRack','BehStorage',PLANT; ...
   'AGVCartPool','SubTransport',PLANT; 'OpsConsole','BehSupervisor',PLANT}; ...
 'PhysicalIronLadle', { ...
   'DualZoneStore','BehStorage',PLANT; 'RoboTransportSwarm','SubTransport',PLANT; ...
   'ControlTriad','BehSupervisor',PLANT; ...
   'ProductionCell1','BehProductionCell',PLANT; 'ProductionCell2','BehProductionCell',PLANT; ...
   'ProductionCell3','BehProductionCell',PLANT; ...
   'ProductionCell1/CellPrepUnit','BehPrepUnit',PLANT; 'ProductionCell1/CellCookVat','BehCookVat',PLANT; ...
   'ProductionCell1/CellQCSensor','BehQCStation',PLANT; 'ProductionCell1/CellPackager','BehPackager',PLANT; ...
   'ProductionCell2/CellPrepUnit','BehPrepUnit',PLANT; 'ProductionCell2/CellCookVat','BehCookVat',PLANT; ...
   'ProductionCell2/CellQCSensor','BehQCStation',PLANT; 'ProductionCell2/CellPackager','BehPackager',PLANT; ...
   'ProductionCell3/CellPrepUnit','BehPrepUnit',PLANT; 'ProductionCell3/CellCookVat','BehCookVat',PLANT; ...
   'ProductionCell3/CellQCSensor','BehQCStation',PLANT; 'ProductionCell3/CellPackager','BehPackager',PLANT}};
plantModels = {'BehPlantHyperCook','BehPlantLeanBroth','BehPlantIronLadle'};

for m = 1:size(maps,1)
    mdlName = maps{m,1};
    mdlA = systemcomposer.loadModel(mdlName);
    entries = maps{m,2};
    for i = 1:size(entries,1)
        comp = lookup(mdlA, 'Path', [mdlName '/' entries{i,1}]);
        if ~hasStereotype(comp, stq), applyStereotype(comp, stq); end
        setProperty(comp, [stq '.BehaviorModel'], entries{i,2});
        setProperty(comp, [stq '.IntegrationLevel'], entries{i,3});
    end
    % Root architecture traces to the variant plant model
    rootArch = mdlA.Architecture;
    if ~hasStereotype(rootArch, stq), applyStereotype(rootArch, stq); end
    setProperty(rootArch, [stq '.BehaviorModel'], plantModels{m});
    setProperty(rootArch, [stq '.IntegrationLevel'], 'plant-composition');
    save(mdlA);
    fprintf('%s: %d behavior traces applied\n', mdlName, size(entries,1) + 1);
end
end
