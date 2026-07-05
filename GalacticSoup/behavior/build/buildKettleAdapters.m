function buildKettleAdapters()
%BUILDKETTLEADAPTERS Link BehCookVat behavior into the LeanBroth kettles.
%   Demonstration of the port-preserving architecture/behavior integration
%   pattern (ADR-017): a dedicated adapter model, BehKettleBehavior.slx,
%   exposes root bus-element ports that MATCH the BatchKettle architecture
%   component's ports by name and interface (preppedBatch, directive,
%   cookedSoup1, statusCook1). linkToModel then syncs ports by name, so
%   the architecture's ports, interfaces, and connectors are all
%   preserved - unlike linking a raw behavioral component model, whose
%   foreign port set would replace the architecture ports.
%
%   Inside the adapter, thin semantic glue maps the architecture's
%   logistics buses to the behavioral layer's continuous-flow signals:
%     preppedBatch.mass_kg [kg/h] -> /(0.55*3600)    -> BehCookVat supply_bps
%     directive.setpoint          -> clamp 0..1      -> BehCookVat enable
%     outflow_bps                 -> *1800 [0.5 L/b] -> cookedSoup1.volume_L
%     vatTemp_C                   ->                 -> cookedSoup1.temp_C
%     state (uint8)               -> double          -> statusCook1.opState
%
%   Vat instance parameters are numeric LeanBroth values (the variant
%   dictionary is not on the architecture model's dictionary chain -
%   accepted duplication, see ADR-017).
%
%   WARNING (ADR-017): linking converts the kettles to reference
%   components, which DROPS their PhysicalProperties stereotype values
%   from the roll-up analysis (LeanBroth loses 90 kW / 1400 kg / the
%   kettles' automation contribution), and R2026a exposes no programmatic
%   way to import the profile into a plain Simulink behavior model to
%   reapply them. The committed baseline therefore keeps the kettles
%   unlinked; run this script on a sandbox branch to reproduce the
%   integration demonstration. Verify afterwards with
%   set_param('PhysicalLeanBroth','SimulationCommand','update').

proj = currentProject;
compDir = char(fullfile(proj.RootFolder, 'behavior', 'components'));
nm = 'BehKettleBehavior';

if bdIsLoaded(nm), close_system(nm, 0); end
f = fullfile(compDir, [nm '.slx']);
if isfile(f), delete(f); end
new_system(nm);
% Architecture interface types (SoupStream etc.) resolve from the physical
% layer's interface dictionary
set_param(nm, 'DataDictionary', 'PhysicalInterfaces.sldd');

add_block('simulink/Ports & Subsystems/In Bus Element', [nm '/In mass'], ...
    'PortName', 'preppedBatch', 'Element', 'mass_kg');
add_block('simulink/Ports & Subsystems/In Bus Element', [nm '/In setpoint'], ...
    'PortName', 'directive', 'Element', 'setpoint');
% Downstream consumers read whole buses, and the emitted element ORDER
% must match the interface bus object - create out-elements in canonical
% order (SoupStream: batchId, volume_L, temp_C, contamination_ppm;
% StatusBus: unitId, opState, faultCode), copying the first block of each
% port to add further elements on the same port.
add_block('simulink/Sinks/Out Bus Element', [nm '/Out batchId'], ...
    'PortName', 'cookedSoup1', 'Element', 'batchId');
add_block([nm '/Out batchId'], [nm '/Out volume']);
set_param([nm '/Out volume'], 'Element', 'volume_L');
add_block([nm '/Out batchId'], [nm '/Out temp']);
set_param([nm '/Out temp'], 'Element', 'temp_C');
add_block([nm '/Out batchId'], [nm '/Out contam']);
set_param([nm '/Out contam'], 'Element', 'contamination_ppm');
add_block('simulink/Sinks/Out Bus Element', [nm '/Out unitId'], ...
    'PortName', 'statusCook1', 'Element', 'unitId');
add_block([nm '/Out unitId'], [nm '/Out state']);
set_param([nm '/Out state'], 'Element', 'opState');
add_block([nm '/Out unitId'], [nm '/Out faultCode']);
set_param([nm '/Out faultCode'], 'Element', 'faultCode');
add_block('simulink/Sources/Constant', [nm '/ZeroA'], 'Value', '0');
add_block('simulink/Sources/Constant', [nm '/ZeroB'], 'Value', '0');
add_block('simulink/Sources/Constant', [nm '/UnitId'], 'Value', '1');
add_block('simulink/Sources/Constant', [nm '/ZeroC'], 'Value', '0');

add_block('simulink/Ports & Subsystems/Model', [nm '/Vat'], ...
    'ModelName', 'BehCookVat', 'SimulationMode', 'Normal');
vatParams = {'BatchSize_bowls','55'; 'HeaterPower_kW','45'; ...
    'VatThermalMass_JpK','130000'; 'FillRate_bps','0.5'; ...
    'SimmerTime_s','1130'; 'DrainTime_s','200'; 'CleanTime_s','120'};
ip = get_param([nm '/Vat'], 'InstanceParameters');
for p = 1:size(vatParams,1)
    ip(strcmp({ip.Name}, vatParams{p,1})).Value = vatParams{p,2};
end
set_param([nm '/Vat'], 'InstanceParameters', ip);

add_block('simulink/Math Operations/Gain', [nm '/MassToBowls'], 'Gain', '1/(0.55*3600)');
add_block('simulink/Discontinuities/Saturation', [nm '/EnableClamp'], ...
    'LowerLimit', '0', 'UpperLimit', '1');
add_block('simulink/Math Operations/Gain', [nm '/BowlsToLitres'], 'Gain', '1800');
add_block('simulink/Signal Attributes/Data Type Conversion', [nm '/StateToDouble'], ...
    'OutDataTypeStr', 'double');
add_block('simulink/Sinks/Terminator', [nm '/TPower']);
add_block('simulink/Sinks/Terminator', [nm '/THopper']);

add_line(nm, 'In mass/1', 'MassToBowls/1');
add_line(nm, 'MassToBowls/1', 'Vat/1');
add_line(nm, 'In setpoint/1', 'EnableClamp/1');
add_line(nm, 'EnableClamp/1', 'Vat/2');
add_line(nm, 'Vat/1', 'BowlsToLitres/1');
add_line(nm, 'BowlsToLitres/1', 'Out volume/1');
add_line(nm, 'Vat/2', 'TPower/1');
add_line(nm, 'Vat/3', 'Out temp/1');
add_line(nm, 'Vat/4', 'StateToDouble/1');
add_line(nm, 'StateToDouble/1', 'Out state/1');
add_line(nm, 'Vat/5', 'THopper/1');
add_line(nm, 'ZeroA/1', 'Out batchId/1');
add_line(nm, 'ZeroB/1', 'Out contam/1');
add_line(nm, 'UnitId/1', 'Out unitId/1');
add_line(nm, 'ZeroC/1', 'Out faultCode/1');
Simulink.BlockDiagram.arrangeSystem(nm);
save_system(nm, f);
if ~any(strcmpi({proj.Files.Path}, f)), addFile(proj, f); end

% Link into both kettle components; ports match by name so the
% architecture interface and connectors are preserved
mdlA = systemcomposer.loadModel('PhysicalLeanBroth');
for k = 1:2
    comp = lookup(mdlA, 'Path', sprintf('PhysicalLeanBroth/BatchKettle%d', k));
    linkToModel(comp, nm);
    portsAfter = sort({comp.Ports.Name});
    assert(isequal(portsAfter, sort({'cookedSoup1','directive','preppedBatch','statusCook1'})), ...
        'BatchKettle%d ports changed by linkToModel: %s', k, strjoin(portsAfter, ', '));
    fprintf('BatchKettle%d -> %s linked, architecture ports preserved\n', k, nm);
end
save(mdlA);
end
