function buildInlineBehaviors(variant)
%BUILDINLINEBEHAVIORS Instantiate behavioral models inside the physical
%   System Composer architectures (ADR-020). Each production-path
%   component receives an inline subsystem behavior (createSubsystemBehavior,
%   which PRESERVES architecture ports, connectors, and stereotype values)
%   containing bus-element ports, thin glue, and a Beh* model reference in
%   Normal mode. Support components receive status stubs so every consumed
%   bus is fully populated. Controllers host BehSupervisor and aggregate
%   plant power/mode into a Telemetry root port.
%
%   buildInlineBehaviors('LeanBroth') | ('HyperCook') | ('EverSimmer')
%
%   Conventions:
%   - Material buses carry flow_bps (bowls-equivalent/s) as the simulated
%     flow; legacy elements are populated with representative constants.
%   - Every out bus is populated in canonical element order (Signal
%     Specification enforces order against the interface bus object).
%   - Faults: each faultable component gates itself with a Step block
%     (Before=1, After=0) at time Fault_T_<Comp> (model-workspace variable,
%     default inf). Override per run via setVariable(...,'Workspace',mdl).
%   - Fixed routing shares at fan-outs (0.5 / 1/3): physical routing is
%     static; supervisor reallocation is deliberately not modeled.
%
%   Destructive and idempotent per component: existing behavior contents
%   (except port blocks) are cleared and rebuilt.

switch variant
    case 'LeanBroth',  buildLeanBroth();
    case 'HyperCook',  buildHyperCook();
    case 'EverSimmer', buildEverSimmer();
    otherwise, error('unknown variant %s', variant);
end
end

% ======================================================================
function buildLeanBroth()
mdl = 'PhysicalLeanBroth';
mdlA = systemcomposer.loadModel(mdl);
set_param(mdl, 'SolverType','Variable-step', 'StopTime','14400');

% fault-time variables (1e9 s = never; Step blocks reject inf)
mws = get_param(mdl,'ModelWorkspace');
for v = {'Fault_T_Prep','Fault_T_Kettle1','Fault_T_Kettle2','Fault_T_QC','Fault_T_Pack'}
    assignin(mws, v{1}, 1e9);
end

% --- TriPadLandingField: resupply source + outbound pass ---
p = beh(mdlA, [mdl '/TriPadLandingField']);
inEl(p,'loadedShipment','flow_bps');
outs = makeOuts(p,'inboundCargo','IngredientPallet', {'palletId','0';'mass_kg','0';'temp_C','4'});
rs = addB(p,'ResupplyRate','simulink/Sources/Constant',{'Value','LB_Resupply_bph/3600'});
line(p, rs, outs('flow_bps'));
outs = makeOuts(p,'outboundShipments','SealedContainerBatch', {'batchId','0';'count','0';'sealRating_days','365'});
passThrough(p, blkOf(p,'loadedShipment'), outs('flow_bps'), 240/3600);
stubStatus(p,'statusFleet', '15', '1');

% --- ManualReceivingBay: rate-capped receive ---
p = beh(mdlA, [mdl '/ManualReceivingBay']);
inEl(p,'inboundCargo','flow_bps');
outs = makeOuts(p,'receivedIngredients','IngredientPallet', {'palletId','0';'mass_kg','0';'temp_C','4'});
passThrough(p, blkOf(p,'inboundCargo'), outs('flow_bps'), 250/3600);
stubStatus(p,'statusReceive', '5', '1');

% --- Storage pair: half the received flow each, BehStorage core ---
storeSpec = {'DryGoodsRack','stagedDry','stockDry','statusDryStore','2'; ...
             'ColdStoreLocker','stagedCold','stockCold','statusColdStore','25'};
for s = 1:2
    p = beh(mdlA, [mdl '/' storeSpec{s,1}]);
    inEl(p,'receivedIngredients','flow_bps');
    inEl(p,'directive','setpoint');
    g = addB(p,'HalfIn','simulink/Math Operations/Gain',{'Gain','0.5'});
    line(p, blkOf(p,'receivedIngredients'), g);
    m = addRef(p,'Store','BehStorage', {'Capacity_bowls','LB_StorageCap_bowls/2'; ...
        'InitLevel_bowls','LB_StorageInit_bowls/2'});
    line(p, g, [m '/1']);
    d = addB(p,'DrawRate','simulink/Sources/Constant',{'Value','LB_PrepRate_bph/2/3600'});
    line(p, d, [m '/2']);
    outs = makeOuts(p, storeSpec{s,2}, 'IngredientPallet', {'palletId','0';'mass_kg','0';'temp_C','4'});
    lineTo(p, [m '/1'], outs('flow_bps'));
    makeOuts(p, storeSpec{s,3}, 'StockData', {'itemId','1';'qty_units','500';'error_pct','0'});
    stubStatus(p, storeSpec{s,4}, storeSpec{s,5}, '1');
    term(p, [m '/2']); term(p, [m '/3']);
end

% --- PrepWorkstation: sum staged flows -> BehPrepUnit ---
p = beh(mdlA, [mdl '/PrepWorkstation']);
inEl(p,'stagedDry','flow_bps'); inEl(p,'stagedCold','flow_bps');
inEl(p,'directive','setpoint');
sm = addB(p,'SupplySum','simulink/Math Operations/Add',{'Inputs','++'});
line(p, blkOf(p,'stagedDry'), sm); lineTo(p, [blkOf(p,'stagedCold') '/1'], [sm '/2']);
gate = faultGate(p, 'Fault_T_Prep');
en = enableOf(p, gate);
m = addRef(p,'Prep','BehPrepUnit', {'PrepRate_bph','LB_PrepRate_bph'});
line(p, sm, [m '/1']); lineTo(p, [en '/1'], [m '/2']);
outs = makeOuts(p,'preppedBatch','PreparedBatch', {'batchId','0';'recipeId','0'});
lineTo(p, [m '/1'], outs('flow_bps'));
kg = addB(p,'ToKgPerHr','simulink/Math Operations/Gain',{'Gain','0.55*3600'});
lineTo(p, [m '/1'], [kg '/1']); lineTo(p, [kg '/1'], outs('mass_kg'));
stubStatus(p,'statusPrep', '12', gate);
term(p, [m '/2']);

% --- BatchKettles: half share each -> BehCookVat (Simscape inside) ---
for k = 1:2
    p = beh(mdlA, sprintf('%s/BatchKettle%d', mdl, k));
    inEl(p,'preppedBatch','flow_bps');
    inEl(p,'directive','setpoint');
    g = addB(p,'HalfShare','simulink/Math Operations/Gain',{'Gain','0.5'});
    line(p, blkOf(p,'preppedBatch'), g);
    gate = faultGate(p, sprintf('Fault_T_Kettle%d', k));
    en = enableOf(p, gate);
    m = addRef(p,'Vat','BehCookVat', {'BatchSize_bowls','LB_BatchSize_bowls'; ...
        'HeaterPower_kW','LB_HeaterPower_kW'; 'VatThermalMass_JpK','LB_VatThermalMass_JpK'; ...
        'FillRate_bps','LB_FillRate_bps'; 'SimmerTime_s','LB_SimmerTime_s'; ...
        'DrainTime_s','LB_DrainTime_s'; 'CleanTime_s','LB_CleanTime_s'});
    line(p, g, [m '/1']); lineTo(p, [en '/1'], [m '/2']);
    outs = makeOuts(p, sprintf('cookedSoup%d',k), 'SoupStream', {'batchId','0';'contamination_ppm','0'});
    lineTo(p, [m '/1'], outs('flow_bps'));
    lit = addB(p,'ToLitres','simulink/Math Operations/Gain',{'Gain','1800'});
    lineTo(p, [m '/1'], [lit '/1']); lineTo(p, [lit '/1'], outs('volume_L'));
    lineTo(p, [m '/3'], outs('temp_C'));
    souts = makeOuts(p, sprintf('statusCook%d',k), 'StatusBus', {'unitId',num2str(k);'faultCode','0'});
    dtc = addB(p,'StateDbl','simulink/Signal Attributes/Data Type Conversion',{'OutDataTypeStr','double'});
    lineTo(p, [m '/4'], [dtc '/1']); lineTo(p, [dtc '/1'], souts('opState'));
    lineTo(p, [m '/2'], souts('power_kW'));
    lineTo(p, [gate '/1'], souts('health'));
    term(p, [m '/5']);
end

% --- QCBench: merge kettles -> surge -> BehQCStation ---
p = beh(mdlA, [mdl '/QCBench']);
inEl(p,'cookedSoup1','flow_bps'); inEl(p,'cookedSoup2','flow_bps');
inEl(p,'directive','setpoint');
sm = addB(p,'SoupSum','simulink/Math Operations/Add',{'Inputs','++'});
line(p, blkOf(p,'cookedSoup1'), sm); lineTo(p, [blkOf(p,'cookedSoup2') '/1'], [sm '/2']);
sg = addRef(p,'Surge','BehStorage', {'Capacity_bowls','150'; 'InitLevel_bowls','0'});
line(p, sm, [sg '/1']);
dr = addB(p,'QCDraw','simulink/Sources/Constant',{'Value','LB_QCRate_bph/3600'});
line(p, dr, [sg '/2']);
gate = faultGate(p, 'Fault_T_QC');
en = enableOf(p, gate);
m = addRef(p,'QC','BehQCStation', {'QCRate_bph','LB_QCRate_bph'; 'RejectFrac','LB_QCReject'; ...
    'CalibPeriod_s','LB_QCCalibPeriod_s'; 'CalibTime_s','LB_QCCalibTime_s'});
lineTo(p, [sg '/1'], [m '/1']); lineTo(p, [en '/1'], [m '/2']);
outs = makeOuts(p,'approvedSoup','SoupStream', {'batchId','0';'temp_C','90';'contamination_ppm','0'});
lineTo(p, [m '/1'], outs('flow_bps'));
lit = addB(p,'ToLitres','simulink/Math Operations/Gain',{'Gain','1800'});
lineTo(p, [m '/1'], [lit '/1']); lineTo(p, [lit '/1'], outs('volume_L'));
stubStatus(p,'statusQA', '3', gate);
term(p, [m '/2']); term(p, [m '/3']); term(p, [sg '/2']); term(p, [sg '/3']);

% --- SemiAutoPackager: surge -> BehPackager ---
p = beh(mdlA, [mdl '/SemiAutoPackager']);
inEl(p,'approvedSoup','flow_bps');
inEl(p,'directive','setpoint');
sg = addRef(p,'Surge','BehStorage', {'Capacity_bowls','80'; 'InitLevel_bowls','0'});
line(p, blkOf(p,'approvedSoup'), sg);
dr = addB(p,'PackDraw','simulink/Sources/Constant',{'Value','LB_PackRate_bph/3600'});
lineTo(p, [dr '/1'], [sg '/2']);
gate = faultGate(p, 'Fault_T_Pack');
en = enableOf(p, gate);
m = addRef(p,'Pack','BehPackager', {'PackRate_bph','LB_PackRate_bph'});
lineTo(p, [sg '/1'], [m '/1']); lineTo(p, [en '/1'], [m '/2']);
outs = makeOuts(p,'sealedContainers','SealedContainerBatch', {'batchId','0';'count','0';'sealRating_days','365'});
lineTo(p, [m '/1'], outs('flow_bps'));
stubStatus(p,'statusPack', '20', gate);
term(p, [sg '/2']); term(p, [sg '/3']);

% --- SharedCraneDock: outbound pass ---
p = beh(mdlA, [mdl '/SharedCraneDock']);
inEl(p,'sealedContainers','flow_bps');
outs = makeOuts(p,'loadedShipment','SealedContainerBatch', {'batchId','0';'count','0';'sealRating_days','365'});
passThrough(p, blkOf(p,'sealedContainers'), outs('flow_bps'), 240/3600);
makeOuts(p,'manifest','ShippingManifestMsg', {'destinationId','0';'batchId','0';'count','0';'mass_kg','0'});
stubStatus(p,'statusDispatch', '18', '1');

% --- OpsConsole: supervisor + telemetry aggregation ---
p = beh(mdlA, [mdl '/OpsConsole']);
inEl(p,'statusCook1','health');
inEl(p,'statusCook2','health');
addInEl(p,'statusCook1','power_kW','Cook1Pwr');
addInEl(p,'statusCook2','power_kW','Cook2Pwr');
powerPorts = {'statusFleet','statusDispatch','statusPower','statusQA','statusReceive', ...
              'statusPack','statusDryStore','statusTransport','statusPrep','statusRefuel','statusColdStore'};
pw = {};
for q = powerPorts
    pw{end+1} = addInEl(p, q{1}, 'power_kW', [q{1} 'Pwr']); %#ok<AGROW>
end
mx = addB(p,'HealthMux','simulink/Signal Routing/Mux',{'Inputs','4'});
one = addB(p,'One','simulink/Sources/Constant',{'Value','1'});
% explicit canonical names: blkOf is ambiguous once extra element readers
% (Cook1Pwr etc.) exist on the same port
line(p, 'in_statusCook1', mx);
lineTo(p, 'in_statusCook2/1', [mx '/2']);
lineTo(p, [one '/1'], [mx '/3']); lineTo(p, [one '/1'], [mx '/4']);
dyn = addB(p,'DynPower','simulink/Math Operations/Add',{'Inputs','++'});
lineTo(p, ['Cook1Pwr' '/1'], [dyn '/1']); lineTo(p, ['Cook2Pwr' '/1'], [dyn '/2']);
sup = addRef(p,'Supervisor','BehSupervisor', {'NumLines','LB_NumLines'});
line(p, mx, sup); lineTo(p, [dyn '/1'], [sup '/2']);
% total power: dynamic + all reported static + unreported units (console 2, grav 30, barcode 1)
tot = addB(p,'TotalPower','simulink/Math Operations/Add', ...
    {'Inputs', repmat('+',1,numel(pw)+2)});
lineTo(p, [dyn '/1'], [tot '/1']);
for q = 1:numel(pw), lineTo(p, [pw{q} '/1'], sprintf('%s/%d', tot, q+1)); end
oth = addB(p,'UnreportedPower','simulink/Sources/Constant',{'Value','33'});
lineTo(p, [oth '/1'], sprintf('%s/%d', tot, numel(pw)+2));
touts = makeOuts(p,'telemetry','TelemetryBus', {});
lineTo(p, [tot '/1'], touts('totalPower_kW'));
mdtc = addB(p,'ModeDbl','simulink/Signal Attributes/Data Type Conversion',{'OutDataTypeStr','double'});
lineTo(p, [sup '/2'], [mdtc '/1']); lineTo(p, [mdtc '/1'], touts('plantMode'));
term(p, [sup '/1']);
makeOuts(p,'productionDirective','ControlBus', {'cmdType','0';'targetId','0';'setpoint','1'});
telemetryRoot(mdlA, [mdl '/OpsConsole'], 'telemetry');

% --- stubs ---
stubOnly(mdlA, [mdl '/CompactFissionReactor'], {'statusPower','0'});
stubOnly(mdlA, [mdl '/RefuelSkid'], {'statusRefuel','8'});
stubOnly(mdlA, [mdl '/AGVCartPool'], {'statusTransport','8'});
p = beh(mdlA, [mdl '/GravityCompUnit']);
makeOuts(p,'envStatus','GravityData', {'gravity_g','1';'compensation_pct','100'});
p = beh(mdlA, [mdl '/BarcodeInventorySystem']);
makeOuts(p,'inventoryStatus','StockData', {'itemId','1';'qty_units','500';'error_pct','0'});
makeOuts(p,'reorderRequest','StockData', {'itemId','1';'qty_units','0';'error_pct','0'});

save(mdlA);
fprintf('%s: inline behaviors built\n', mdl);
end

% ======================================================================
function buildHyperCook() %#ok<DEFNU>
error('HyperCook section not yet written');
end
function buildEverSimmer() %#ok<DEFNU>
error('EverSimmer section not yet written');
end

% ======================= helpers =======================
function p = beh(mdlA, path)
% ensure subsystem behavior exists, clear previous contents (keep ports)
[~, compName] = fileparts(path);
comp = lookup(mdlA, 'Path', path);
try, createSubsystemBehavior(comp); catch, end   % idempotent
inner = find_system(path,'SearchDepth',1,'LookUnderMasks','all');
seenPorts = {};
for i = 2:numel(inner)
    bt = get_param(inner{i},'BlockType');
    if ~any(strcmp(bt,{'Inport','Outport'}))
        delete_block(inner{i});
    else
        % keep exactly one bus-element block per (direction, port name);
        % extra element readers/writers from a previous build are rebuilt
        key = [bt ':' get_param(inner{i},'PortName')];
        if any(strcmp(seenPorts, key))
            delete_block(inner{i});
        else
            seenPorts{end+1} = key; %#ok<AGROW>
        end
    end
end
delete_line(find_system(path,'SearchDepth',1,'FindAll','on','Type','line'));
% canonical names so rebuild block names never collide with survivors
for c = find_system(path,'SearchDepth',1,'BlockType','Inport')'
    set_param(c{1}, 'Name', ['in_' get_param(c{1},'PortName')]);
end
for c = find_system(path,'SearchDepth',1,'BlockType','Outport')'
    set_param(c{1}, 'Name', ['out_' get_param(c{1},'PortName')]);
end
p = path; %#ok<NASGU>
p = path;
fprintf('  [%s]\n', compName);
end

function b = blkOf(p, portName)
% the In Bus Element block for a given input port
for c = find_system(p,'SearchDepth',1,'BlockType','Inport')'
    if strcmp(get_param(c{1},'PortName'), portName), b = get_param(c{1},'Name'); return; end
end
error('no in port block for %s in %s', portName, p);
end

function b = inEl(p, portName, element)
b = blkOf(p, portName);
set_param([p '/' b], 'Element', element);
end

function b = addInEl(p, portName, element, newName)
% additional element reader on an existing input port (copy the original)
src = blkOf(p, portName);
add_block([p '/' src], [p '/' newName]);
set_param([p '/' newName], 'Element', element);
b = newName;
end

function outs = makeOuts(p, portName, intfName, constPairs)
% populate an output bus port in canonical element order; elements listed
% in constPairs get Constant sources; the rest are returned for wiring.
canon = struct( ...
  'IngredientPallet', {{'palletId','mass_kg','temp_C','flow_bps'}}, ...
  'PreparedBatch',    {{'batchId','recipeId','mass_kg','flow_bps'}}, ...
  'SoupStream',       {{'batchId','volume_L','temp_C','contamination_ppm','flow_bps'}}, ...
  'SealedContainerBatch', {{'batchId','count','sealRating_days','flow_bps'}}, ...
  'StatusBus',        {{'unitId','opState','faultCode','power_kW','health'}}, ...
  'ControlBus',       {{'cmdType','targetId','setpoint'}}, ...
  'StockData',        {{'itemId','qty_units','error_pct'}}, ...
  'GravityData',      {{'gravity_g','compensation_pct'}}, ...
  'ShippingManifestMsg', {{'destinationId','batchId','count','mass_kg'}}, ...
  'TelemetryBus',     {{'totalPower_kW','plantMode'}});
els = canon.(intfName);
% first writer: existing port block if present, else fresh block creates port
first = '';
for c = find_system(p,'SearchDepth',1,'BlockType','Outport')'
    if strcmp(get_param(c{1},'PortName'), portName), first = get_param(c{1},'Name'); break; end
end
if isempty(first)
    first = [portName '_el1'];
    add_block('simulink/Sinks/Out Bus Element', [p '/' first], 'PortName', portName);
end
outs = containers.Map();
for i = 1:numel(els)
    if i == 1
        set_param([p '/' first], 'Element', els{i});
        bn = first;
    else
        bn = sprintf('%s_el%d', portName, i);
        add_block([p '/' first], [p '/' bn]);
        set_param([p '/' bn], 'Element', els{i});
    end
    outs(els{i}) = bn;
end
% wire the constants
for i = 1:size(constPairs,1)
    cn = sprintf('%s_c%d', portName, i);
    add_block('simulink/Sources/Constant', [p '/' cn], 'Value', constPairs{i,2});
    add_line(p, [cn '/1'], [outs(constPairs{i,1}) '/1']);
end
end

function b = addB(p, name, lib, params)
add_block(lib, [p '/' name]);
for i = 1:size(params,1)
    set_param([p '/' name], params{i,1}, params{i,2});
end
b = name;
end

function m = addRef(p, name, refModel, instParams)
add_block('simulink/Ports & Subsystems/Model', [p '/' name], ...
    'ModelName', refModel, 'SimulationMode', 'Normal');
if ~isempty(instParams)
    ip = get_param([p '/' name], 'InstanceParameters');
    for i = 1:size(instParams,1)
        k = strcmp({ip.Name}, instParams{i,1});
        assert(any(k), 'no arg %s on %s', instParams{i,1}, refModel);
        ip(k).Value = instParams{i,2};
    end
    set_param([p '/' name], 'InstanceParameters', ip);
end
m = name;
end

function g = faultGate(p, varName)
% health gate: 1 until Fault_T, 0 after
g = ['Gate_' varName];
add_block('simulink/Sources/Step', [p '/' g], ...
    'Time', varName, 'Before', '1', 'After', '0');
end

function en = enableOf(p, gate)
% enable = directive.setpoint * fault gate (setpoint reader must exist)
en = ['En_' gate];
add_block('simulink/Math Operations/Product', [p '/' en]);
sp = blkOf(p, 'directive');
add_line(p, [sp '/1'], [en '/1']);
add_line(p, [gate '/1'], [en '/2']);
end

function passThrough(p, srcBlk, dstBlk, cap)
s = [srcBlk 'Cap'];
add_block('simulink/Discontinuities/Saturation', [p '/' s], ...
    'LowerLimit','0','UpperLimit', num2str(cap, 12));
add_line(p, [srcBlk '/1'], [s '/1']);
add_line(p, [s '/1'], [dstBlk '/1']);
end

function stubStatus(p, portName, powerVal, healthSrc)
outs = makeOuts(p, portName, 'StatusBus', {'unitId','1';'opState','1';'faultCode','0';'power_kW',powerVal});
if ischar(healthSrc) && ~isempty(str2double(healthSrc)) && ~isnan(str2double(healthSrc))
    cn = [portName '_h'];
    add_block('simulink/Sources/Constant', [p '/' cn], 'Value', healthSrc);
    add_line(p, [cn '/1'], [outs('health') '/1']);
else
    add_line(p, [healthSrc '/1'], [outs('health') '/1']);
end
end

function stubOnly(mdlA, path, statusSpec)
p = beh(mdlA, path);
for i = 1:size(statusSpec,1)
    stubStatus(p, statusSpec{i,1}, statusSpec{i,2}, '1');
end
end

function line(p, a, b)
if ~contains(a, '/'), a = [a '/1']; end
if ~contains(b, '/'), b = [b '/1']; end
add_line(p, a, b);
end
function lineTo(p, aPort, bPort)
% aPort like 'Blk/2', bPort like 'Blk/1'
if ~contains(bPort, '/'), bPort = [bPort '/1']; end
if ~contains(aPort, '/'), aPort = [aPort '/1']; end
add_line(p, aPort, bPort);
end
function term(p, srcPort)
persistent n
if isempty(n), n = 0; end
n = n + 1;
t = sprintf('Trm%d', n);
add_block('simulink/Sinks/Terminator', [p '/' t]);
add_line(p, srcPort, [t '/1']);
end

function telemetryRoot(mdlA, compPath, portName)
% route the controller's telemetry port to a root Telemetry output port
mdl = mdlA.Name;
comp = lookup(mdlA, 'Path', compPath);
cp = [];
for q = comp.Ports
    if strcmp(q.Name, portName), cp = q; break; end
end
assert(~isempty(cp), 'port %s not yet visible on %s (save/reload the model first)', portName, compPath);
% no explicit interface: the element-writer blocks type the port, and a
% whole-interface assignment conflicts with element-specified ports
arch = mdlA.Architecture;
rp = [];
for q = arch.Ports
    if strcmp(q.Name, 'Telemetry'), rp = q; break; end
end
if isempty(rp)
    rp = addPort(arch, 'Telemetry', 'out');
end
try, connect(cp, rp); catch, end   % idempotent
fprintf('  telemetry routed to root (%s)\n', mdl);
end
