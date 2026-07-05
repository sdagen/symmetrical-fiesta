# 07 — Decision Log

Architecture Decision Record (ADR) style log for the Intergalactic Vegan Soup Factory RFLP model. Each entry records the context, the decision, and its consequences.

---

## ADR-001: Three separate physical `.slx` models per variant, not System Composer variant components

**Context.** The physical layer needs to represent three competing architecture concepts (HyperCook, LeanBroth, IronLadle) for a trade study. System Composer supports representing design alternatives either as separate models or as `Variant` components/choices within a single model.

**Decision.** Model each physical variant as its own standalone model (`PhysicalHyperCook.slx`, `PhysicalLeanBroth.slx`, `PhysicalIronLadle.slx`) rather than as `Variant` components inside one shared physical model.

**Consequences.** Each variant can be rolled up (mass/power/cost/volume/throughput totals) and have requirements allocated independently, without needing to activate/deactivate variant choices to analyze one concept at a time. Comparison across variants is done externally (roll-up + MCDA trade study) rather than via System Composer's built-in variant-choice mechanism. The cost is some duplication: each model repeats the same 12-component topology inherited from the logical layer, and any topology-level fix must be applied three times (or scripted). This tradeoff was accepted because the variants differ enough in internal structure (e.g., IronLadle triplicates prep/cook/QC/packaging per cell, while HyperCook and LeanBroth do not) that a single shared-topology variant model would not cleanly express the differences without extensive internal variant nesting.

---

## ADR-002: Functional ↔ logical realization is 1:1 at this abstraction level

**Context.** The logical architecture must realize each of the 12 functional-layer functions as one or more logical components. Options ranged from 1:1 realization to splitting/merging functions across logical components.

**Decision.** Realize each function as exactly one logical component (see [`03_logical_architecture.md`](03_logical_architecture.md) §2), with matching names and topology across the functional and logical models.

**Consequences.** Full requirement traceability is preserved end-to-end (SR → function → logical component) with no ambiguity. The logical layer's value at this level is entirely in typing the interfaces (see [`03_logical_architecture.md`](03_logical_architecture.md) §3) and naming solution roles, not in restructuring the topology. This is appropriate because the functions were already defined at system-component granularity; if a future refinement finds that one function should be split (e.g., decomposing `TransportMaterialsInternally` into per-zone transport components) or that several functions should be merged behind a shared logical unit, the 1:1 mapping would need to be revisited at that point — it is not treated as a fixed rule for all future work, only the appropriate choice for this system level today.

---

## ADR-003: Status fan-in modeled as separate named ports on `ProductionControlSystem`

**Context.** `CoordinateProduction`/`ProductionControlSystem` needs to receive an `OperationalStatus`/`UnitStatus` report from each of the other 11 functions/components. System Composer does not provide merge-block semantics for combining multiple signal sources onto a single port the way some other modeling tools do.

**Decision.** Model the status fan-in as 11 separate, individually named input ports on `ProductionControlSystem` (one per reporting function/component), rather than attempting to merge them onto a single status port.

**Consequences.** Every status source is individually traceable and addressable in analysis and (later) simulation — no ambiguity about which component's status is being read. The port list on `ProductionControlSystem` is correspondingly large (11 status inputs plus 11 command outputs), which is visually busier than a single merged port would be, but this is a direct, faithful representation of the star topology rather than a workaround, and avoids hiding fan-in behavior behind a modeling construct System Composer does not natively support.

---

## ADR-004: Internal transport modeled as a coordination service function, not inline on the material chain

**Context.** `TransportMaterialsInternally` (SR-GS-023, SR-GS-024) represents the automated movement of materials between receiving, storage, prep, cooking, packaging, and dispatch. It could have been modeled either as literal point-to-point transport blocks interposed on every link of the material chain, or as a separate coordination-style function.

**Decision.** Draw the primary material chain as direct point-to-point flows between the processing functions (`ReceiveInboundDeliveries` → `StoreIngredients` → `PrepareIngredients` → `CookSoup` → `AssureQuality` → `PackageSoup` → `DispatchShipments`), and model `TransportMaterialsInternally` separately as a function that receives a `ControlDirective` and reports `OperationalStatus`, representing the transport *capability* and its automation/rate requirements rather than inserting it as a literal block on every material link.

**Consequences.** The material chain diagram stays readable as a clear pipeline instead of being interrupted by a transport block between every pair of stages. SR-GS-023 (transfer rate) and SR-GS-024 (automation percentage) are traced to a single, clearly identifiable function/component rather than being split across multiple inline transport instances. The physical variants are free to realize this capability differently — HyperCook as a high-speed conveyor network, LeanBroth as shared AGV carts, IronLadle as autonomous robotic transport (see [`04_physical_variants.md`](04_physical_variants.md)) — without those choices affecting the functional or logical topology.

---

## ADR-005: Gravity compensation as an explicit function, `CompensateGravity`

**Context.** SR-GS-015 (0.1 g-12 g operating range) and SR-GS-016 (12 g structural tolerance) derive from SN-GS-008 (gravity range) and could have been treated as a non-functional/structural constraint applied uniformly across all functions rather than as a function in its own right.

**Decision.** Model gravity compensation as its own function, `CompensateGravity`, taking the root `AmbientGravity` input and reporting `EnvironmentState`/`GravityState` into the production-coordination status fan-in, realized at the logical layer as `GravityCompensationSystem`.

**Consequences.** SR-GS-015 and SR-GS-016 get first-class traceability to a specific function/component instead of being scattered as an implicit assumption across all 12 functions. Production coordination can explicitly react to gravity/environment state alongside throughput and fault status. The tradeoff is that every physical variant must still separately account for gravity-driven structural margin in its own equipment (mounts, structure) — `CompensateGravity`/`GravityCompensationSystem` captures the sensing/compensation behavior, not a substitute for structural design margin in every other component.

---

## ADR-006: Power generation modeled only at the physical layer

**Context.** All three physical variants include a power source (fusion plant, fission reactor, redundant reactors), driven by the power budget SR-GS-012. This could have been represented as a functional-layer function (e.g., `GeneratePower`) or introduced only at the physical layer.

**Decision.** Do not create a functional-layer function or logical-layer component for power generation. Power sources appear only in the physical variant models as physical-only components with no functional/logical counterpart.

**Consequences.** SR-GS-012 (power budget) is treated purely as a resource constraint to be verified by roll-up analysis at the physical layer, consistent with how the other three budget requirements (mass, cost, volume — SR-GS-011, SR-GS-013, SR-GS-014) are handled (none of the four budget SRs are allocated to a function; see [`02_functional_architecture.md`](02_functional_architecture.md) §2). This keeps the functional/logical layers focused on what the system *does* rather than what powers it, and keeps power source selection (fusion vs. fission vs. redundant fission) purely a physical/implementation decision that differentiates the variants without requiring functional or logical model changes.

---

## ADR-007: A single `PhysicalProperties` stereotype for all quantitative roll-up properties

**Context.** Each physical component across all three variants needs quantitative properties (mass, power, cost, volume, throughput, automation level, operators required, MTBF, gravity rating, and whether its throughput parallelizes) to support a uniform roll-up analysis and the downstream MCDA trade study.

**Decision.** Define one stereotype, `PhysicalProperties` (profile `GalacticSoupProfile`), carrying all ten properties (`Mass_kg`, `Power_kW`, `Cost_kCredits`, `Volume_m3`, `Throughput_bph`, `AutomationLevel`, `OperatorsRequired`, `MTBF_hr`, `GravityRating_g`, `UseParallelThroughput`), and apply it uniformly to every component in every physical variant model, rather than defining separate stereotypes per component category (e.g., one for production equipment, one for infrastructure, one for power).

**Consequences.** Roll-up analysis code and the MCDA trade study can iterate over all physical components uniformly, reading the same property set regardless of variant or component type, without per-category special-casing. Some properties will be not-applicable or zero for some components (e.g., `Throughput_bph`/`UseParallelThroughput` for a power plant, `GravityRating_g` for a purely electronic controller); this is accepted as a minor modeling simplification in exchange for uniform, mechanical roll-up logic across all three variants.

---

## ADR-008: Seven-criterion min-max weighted-sum MCDA with Dirichlet Monte Carlo sensitivity

**Context.** The trade study needs to rank three compliant physical variants (HyperCook, LeanBroth, IronLadle) that each excel on a different axis (throughput/logistics, resource budgets, resilience/autonomy respectively; see [`04_physical_variants.md`](04_physical_variants.md)). A scoring method was needed that (a) is transparent enough for stakeholders to audit the ranking rationale, (b) is anchored directly to the system requirements rather than ad hoc judgment, and (c) does not silently bake in whichever single weighting the analyst happens to pick.

**Decision.** Score the variants with a seven-criterion, min-max normalized, weighted-sum MCDA (ThroughputMargin, ResourceMargin, CostMargin, Automation, CrewMargin, Availability, N1Retention — each traceable to a specific SR or SR group), evaluated under four named stakeholder weighting scenarios (Balanced, ThroughputFirst, CostLean, MissionAssurance), and cross-checked with a 5,000-sample Dirichlet random-weight Monte Carlo sweep (`rng(42)`) reporting each variant's win share across the full space of plausible weightings. Full method detail is in [`05_trade_study_methodology.md`](05_trade_study_methodology.md).

**Consequences.** Every criterion and every scenario weight is traceable back to a requirement or an explicit stakeholder priority statement, so the scoring is auditable rather than a black box — anyone can recompute a variant's score from its raw metrics and the published weights. The Monte Carlo sweep guards against weight-picking bias: a variant that only wins because of how the four named scenarios happen to be weighted would show a correspondingly modest Monte Carlo win share, whereas a robust winner wins across most of the weighting space (as IronLadle does, at 84%; see [`06_trade_study_results.md`](06_trade_study_results.md) §5). The cost of this approach is the threats to validity documented in [`05_trade_study_methodology.md`](05_trade_study_methodology.md) §4 — min-max normalization is relative to this specific 3-variant set, and the method still depends on point-estimate stereotype properties and hand-authored stage tables rather than stochastic simulation.

---

## ADR-009: Select IronLadle as the baseline physical architecture

**Context.** The trade study (ADR-008, [`06_trade_study_results.md`](06_trade_study_results.md)) is complete and all three variants are SR-compliant (all 8 gates pass for HyperCook, LeanBroth, and IronLadle). A single variant must be selected as the baseline to carry forward into detailed design.

**Decision.** Select IronLadle (Variant C) as the baseline physical architecture. IronLadle wins 3 of the 4 named MCDA scenarios (Balanced 0.671, ThroughputFirst 0.585, MissionAssurance 0.812 — all highest of the three variants) and 84% of the 5,000-sample Monte Carlo weight sensitivity sweep, versus 5.0% for HyperCook and 11.0% for LeanBroth — the most robust result across the plausible range of stakeholder priorities. It is the only variant with any single-fault graceful degradation (66.7% N-1 capacity retention vs. 0% for both other variants) and leads on automation (0.956) and availability (0.9789).

**Status.** Accepted.

**Consequences.** Detailed design proceeds against the IronLadle triplicated-cell topology (3 independent production cells, distributed control triad, redundant reactor pair; see [`04_physical_variants.md`](04_physical_variants.md) §3). Three follow-up actions carry forward from the caveats identified in [`06_trade_study_results.md`](06_trade_study_results.md) §7-8: (1) negotiate a cost reserve or descope items to widen IronLadle's thin 4.7% cost margin before vendor costs for triplicated equipment are locked in; (2) define a degraded-mode operations procedure for the 160 bph single-cell-loss contingency, documented explicitly as a below-nominal contingency state rather than a compliant alternative to the SR-GS-002 200 bph floor; (3) carry LeanBroth as a documented descope option, since it wins the CostLean scenario (0.615) and takes 11% of Monte Carlo draws, making it the next-best alternative if budget priorities come to dominate over throughput or resilience.

---

## ADR-010: Formalize the eight SR compliance gates as a generated Requirements Table model

**Context.** The baseline analysis chain evaluates SR compliance as procedural MATLAB comparisons inside `runVariantAnalysis.m`. Those checks are correct but invisible to the Requirements Toolbox ecosystem: they carry no traceability links, produce no formal artifacts, and their fidelity to the requirement text depends on code review alone. Requirements Toolbox offers the Requirements Table block for expressing formal, machine-checkable requirements inside a Simulink model. Candidate uses for the variant architectures included per-variant behavioral requirements, stimulus/response verification of future behavior models, and formalizing the system-level quantitative gates.

**Decision.** Use a single Requirements Table block, in a dedicated generated model (`GalacticSoupComplianceGate.slx`), to formalize the eight quantitative SR gates (mass, power, cost, volume, throughput, automation, operators, gravity). The variants' rolled-up metrics enter as design-output inputs; caps are Parameter symbols resolved from the model workspace, populated at build time by parsing the requirement text (same `gsParseBudgetValue` mechanism as the roll-up analysis); each formal row carries a Refine link to its source SR. The model is exclusively generated by `buildComplianceGate.m` and rebuilt whenever requirements change, never hand-edited. Behavioral uses of the block are deferred until architecture components have behavior models. Full detail in [`08_formal_compliance_gate.md`](08_formal_compliance_gate.md).

**Consequences.** The eight most load-bearing SRs in the project are now executable, linked artifacts rather than conventions inside analysis code, and the Requirements Editor shows the formal refinement of each gated SR. The generate-don't-edit rule preserves the single-source-of-truth property for caps and makes the model disposable/reproducible, at the cost that manual edits to the gate model are forbidden (they would be silently destroyed on rebuild) and the generator must handle Requirements Table API subtleties (design-output flags, placeholder-row removal, zombie link cleanup on rebuild; see [`08_formal_compliance_gate.md`](08_formal_compliance_gate.md) §5).

---

## ADR-011: Formal gate runs as a blocking stage between roll-up and trade study, cross-checked against procedural flags

**Context.** With both a procedural compliance path (`OK_*` flags in `runVariantAnalysis.m`) and a formal path (the Requirements Table gate) available, the chain needed a defined relationship between them: replace one with the other, or run both.

**Decision.** Keep both and make them check each other. `runFullAnalysis.m` sequences roll-up, then `runComplianceGate.m`, then the trade study. The gate harness hard-errors if any formal verdict disagrees with the corresponding procedural flag, and the trade study refuses to run if any variant fails the formal gate.

**Status.** Accepted.

**Consequences.** Compliance is established by two independently implemented mechanisms that must agree, so a drift in either (a stale cap constant, a mis-generated postcondition, a changed requirement not propagated) fails loudly instead of silently skewing the trade study. The trade study's precondition (only compliant variants are scored) is now enforced by the pipeline rather than by analyst discipline. The cost is one extra simulation per variant per full run (negligible: a one-step discrete sim of a table block) and the standing obligation to rebuild the gate model when requirement caps change.

---

## ADR-012: Behavioral layer as a shared component library of referenced models, not per-variant monoliths

**Context.** Raising the physical variants to executable behavior (Simulink dynamics, Stateflow supervisory/batch logic, Simscape thermal physics — see [`09_behavioral_models.md`](09_behavioral_models.md)) could have been built as three independent monolithic behavior models mirroring the three physical variant models, or as a shared library of reusable component models composed differently per variant.

**Decision.** Build the behavioral layer as a shared component library: eight model references (`BehStorage`, `BehPrepUnit`, `BehCookLine`, `BehCookVat`, `BehQCStation`, `BehPackager`, `BehSupervisor`, `BehProductionCell`) plus two subsystem references (`SubTransport`, `SubFaultGate`), using the System Composer architecture components as the componentization guide (one behavioral component per recurring production role, not per physical part).

**Consequences.** Each component is unit-testable in isolation ([`09_behavioral_models.md`](09_behavioral_models.md) §6), so a bug is caught and fixed once instead of three times across variant-specific copies — this is exactly the mechanism that surfaced the supervisor vector-size bug (§6) before it could hide inside a monolith. Variants differ only by composition (which components, how many instances) and parameter binding (ADR-016), not by independently-authored logic, which keeps the three plant models thin and auditable. The cost is upfront design discipline: every component's interface has to be generic enough to serve all three variants' uses of that production role, which was not free (see ADR-013 on `SubTransport`'s generic parameter naming).

---

## ADR-013: Model references for stateful roles, subsystem references for small stateless utilities

**Context.** Ten behavioral building blocks were needed. Simulink offers two component-reuse mechanisms with different tradeoffs: model references (separate compiled unit, independent simulation and testing, model arguments for parameterization, but per-instance file/interface overhead) and subsystem references (lighter weight, no separate top-level interface, shared parameters via masks).

**Decision.** Use model references for the eight stateful production-role components (`BehStorage` through `BehProductionCell`). Use subsystem references for the two small, stateless, cross-cutting utilities: `SubTransport` (transfer-rate saturation + latency) and `SubFaultGate` (health/enable gating of a flow). `SubTransport` is parameterized by generically-named dictionary entries (`Transport_Rate_bph`, `Transport_Latency_s`) resolved from whichever variant dictionary the linking plant carries, rather than by a mask — so one transport spec per plant is sufficient with no per-instance mask dialog.

**Consequences.** The stateful roles get independent unit tests and per-instance model-argument parameterization exactly where that machinery earns its keep (§6, §7 of [`09_behavioral_models.md`](09_behavioral_models.md)); the two utilities avoid the ceremony of a full model-reference interface for logic that is a few blocks deep and carries no internal state worth isolating. The generic dictionary-entry naming for `SubTransport` means it makes no assumption about which physical transport concept (conveyor, AGV pool, robotic swarm) it stands in for — it reads whatever rate/latency the current variant's dictionary defines, which keeps it reusable without a mask at the cost of requiring every variant dictionary to define both entries under those exact names.

---

## ADR-014: Continuous-flow abstraction instead of SimEvents entities

**Context.** Material flow through the behavioral models could be represented as discrete entities (SimEvents, giving per-bowl or per-batch fidelity) or as continuous rate signals (bowls/second, giving a lighter-weight simulation closer to the rate-based metrics the trade study already consumes).

**Decision.** Model material as continuous rate signals in bowls/second (bowl-equivalents for pre-cook material), with time in seconds. Reject SimEvents.

**Consequences.** The models integrate cleanly with Simscape (BehCookVat's thermal network) and Stateflow (batch sequencing, supervisory modes) without an entity-to-signal conversion layer, and the reported metrics — throughput in bph, energy per bowl — are natural continuous-signal quantities rather than derived from entity statistics. The batchiness that actually matters for the trade study (cycle time and thermal energy, which distinguish batch from continuous cooking) is captured directly in the BehCookVat sequencer rather than lost to the continuous abstraction. The cost, documented as a threat to validity in [`10_behavioral_trade_update.md`](10_behavioral_trade_update.md) §7, is that discrete-batch queueing effects at shared downstream resources are not represented, and buffer overflow currently discards excess flow rather than backing pressure up the chain (no SimEvents-style blocking).

---

## ADR-015: Simscape thermal physics confined to BehCookVat; all model references run in Normal simulation mode

**Context.** Two related decisions arose while adding physical fidelity: which components, if any, warrant Simscape modeling beyond load-scaled power draw; and which simulation mode (Normal vs. Accelerator) the model-reference component library should run in.

**Decision.** Simscape thermal physics (heater source, lumped thermal mass, convective loss, fresh-charge exchange) is modeled only in `BehCookVat` — the one place where heat-up time and simmer energy differentiate batch from continuous cooking. Simscape Electrical power-network modeling is rejected as fidelity without a consumer; every other component's power is load-scaled or static draw from the existing stereotype values. Separately, all model references run in **Normal** simulation mode, never Accelerator.

**Consequences.** Thermal modeling effort is spent exactly where it changes a metric the trade study reads (energy per bowl, time-to-first-output for batch plants), and is skipped everywhere it would add cost without changing a result. The Normal-mode decision was forced empirically ([`09_behavioral_models.md`](09_behavioral_models.md) §7): Accelerator targets inline "non-tunable expressions," and transfer-function denominators and Constant-block expressions referencing model arguments either error or silently freeze a stale value shared across instances under acceleration — a silent per-instance-parameter corruption risk judged unacceptable for the accuracy the accelerator speedup would buy. Simulation of the full plant models is correspondingly slower than an all-Accelerator configuration would be, accepted as the cost of correct per-instance parameterization.

---

## ADR-016: Parameterization contract — model arguments plus a layered dictionary chain, mode codes as uint8 constants

**Context.** Ten reusable components need per-variant, per-instance parameter values (rates, capacities, thermal constants, mode/state codes) without hard-coding any variant's numbers into shared component logic.

**Decision.** Component models declare **model arguments** (instance parameters) with neutral defaults in their model workspaces. A layered data dictionary chain — `BehaviorInterfaces.sldd` (shared types) ⊂ `BehParamsCommon.sldd` (soup/thermal physics constants) ⊂ `BehParams<Variant>.sldd` (per-variant instance parameters, one dictionary per variant, each referencing Common) — supplies the actual values. Variant plant models link their variant dictionary and bind each model-reference instance's arguments to named dictionary entries; component models themselves link only `BehaviorInterfaces.sldd` + `BehParamsCommon.sldd` and carry no variant knowledge. Mode/state codes (plant modes, vat states) are `uint8` dictionary constants rather than MATLAB enumeration classes.

**Consequences.** Components stay reusable and independently testable because they never reference a variant dictionary directly — swapping variants is purely a matter of which dictionary the plant links and which entries it binds, with no component-model edits. The neutral-default-plus-binding pattern means a component can be unit-tested standalone with sensible defaults, with no variant dictionary loaded at all. Choosing `uint8` constants over enumeration classes was a dictionary-friendliness tradeoff: enum classes require a `.m` class definition file on the MATLAB path, which does not travel cleanly through a data dictionary the way a plain constant does; the cost is losing the enum's named-value readability at the workspace level (mode `2` rather than `PlantMode.Degraded`) in exchange for dictionary portability.

---

## ADR-017: Architecture/behavior integration — plant-level execution, port-preserving adapters, and a BehaviorRealization stereotype

**Context.** The behavioral component library ([`09_behavioral_models.md`](09_behavioral_models.md)) needed to connect back into the System Composer physical architecture models, and System Composer's native `linkToModel` mechanism for attaching a Simulink model as a component's behavior has a destructive default (see below) that had to be worked around.

**Decision.** Three-part integration approach. (a) **Executable integration at plant level** — the `BehPlant*` top models are the primary executable artifacts, composed directly from the component library rather than wired through the architecture models. (b) **Port-preserving `linkToModel`** via an adapter behavior model whose root ports are bus-element ports matching the target component's existing port names and interfaces exactly; implemented and verified on both LeanBroth kettles, where `BehKettleBehavior` wraps `BehCookVat` plus semantic glue converting between the architecture's logistics buses and the component library's flow signals. With the name-matched bus-element ports in place, `linkToModel` preserved every existing port, interface, and connector, and the full LeanBroth architecture compiled cleanly with live Simscape kettle behavior in the loop. Linking was subsequently reverted for the committed baseline — see Consequences — because of a rollup-breaking side effect discovered only after this verification. (c) A `BehaviorRealization` stereotype (properties `BehaviorModel`, `IntegrationLevel`) applied to 40 components/roots across the three physical models, giving machine-readable traceability from architecture component to behavioral artifact regardless of which of (a)/(b) applies; on the two LeanBroth kettles this trace now carries `IntegrationLevel` = `'adapter-available'` rather than a live link.

**Consequences.** Rejected alternatives: raw `linkToModel` without a matching-port adapter, because System Composer's `linkToModel` **replaces** a component's architecture ports with the linked Simulink model's root ports whenever names don't already match — destroying the architecture-level interface silently; and full-fleet inline adapters for every component (mechanical repetition with no new information per instance), deferred rather than built now. The accepted debt is numeric parameter duplication inside `BehKettleBehavior`: because the architecture model's dictionary chain does not include the variant behavioral parameter dictionaries, the adapter's semantic-glue constants are hand-duplicated rather than dictionary-bound, and must be kept in sync manually if the underlying variant parameters change. `createSubsystemBehavior`'s R2026a limitations (no filename argument, inline behavior refuses algorithm blocks) ruled out the simplest-looking alternative before the adapter pattern was adopted.

**Late finding — linking dropped the kettles out of the roll-up, and R2026a cannot reprogram the fix.** After (b) was verified, rolling up `PhysicalLeanBroth` with the kettles actually linked showed that `linkToModel` converts the target component into a *reference component*, and reference components' `PhysicalProperties` stereotype property values are silently excluded from the roll-up analysis. LeanBroth lost 90 kW of power and 1,400 kg of mass along with both kettles' automation contribution — the automation average fell from 0.800 to 0.700, tripping a second, purely artifactual compliance gate failure on top of the genuine LeanBroth throughput failure (§3 of [`10_behavioral_trade_update.md`](10_behavioral_trade_update.md)). Re-applying the stereotype to the now-linked components was investigated as a fix and rejected: R2026a exposes no programmatic API to import a `GalacticSoupProfile` profile into a plain Simulink behavior model (the Profile Editor UI can do this interactively; `set_param(..., 'Profile', ...)` is the code profiler, unrelated to System Composer profiles), so the dropped values cannot be reapplied to a linked component by script. **Decision:** the committed baseline keeps both LeanBroth kettles **unlinked** (restored from git), preserving the stereotype-driven roll-up's integrity. `BehKettleBehavior.slx` and `behavior/build/buildKettleAdapters.m` remain in the repository as the verified, reproducible demonstration of the port-preserving pattern — the build script reproduces the linked configuration on demand for sandbox use, and it ran successfully with `PhysicalLeanBroth` passing update-diagram against live Simscape kettle behavior before the revert. Traceability to that demonstration is carried by the `BehaviorRealization` stereotype's `IntegrationLevel` = `'adapter-available'` on the two kettles (10 `BehaviorRealization` traces total on `PhysicalLeanBroth`). With the revert in place, the analysis chain reproduces the intended baseline exactly: the formal gate is 23/24, with only LeanBroth's Throughput row failing.

---

## ADR-018: Behavioral metrics override static roll-up values; gate failures exclude rather than block

**Context.** With simulated throughput and worst-case single-fault retention now available from `runBehavioralAnalysis.m`, the roll-up needed a policy for how these interact with the existing static stage-table values and the existing all-or-nothing compliance gate (ADR-011: the trade study refuses to run if any variant fails). The behavioral throughput numbers are lower than the static ones for every variant (yield loss and downtime the static tables never modeled — [`10_behavioral_trade_update.md`](10_behavioral_trade_update.md) §2), and this pushed LeanBroth below the SR-GS-002 throughput floor for the first time.

**Decision.** Simulated throughput and N-1 retention replace the corresponding static values in `runVariantAnalysis`'s rolled-up metrics; the static values are retained alongside them (`Static_*` fields) rather than discarded, for comparison. Gate policy changes from "any failure blocks everything" to "failed variants are excluded from MCDA scoring, and the chain continues" for the remaining compliant variants, requiring at least two compliant variants to proceed.

**Consequences.** A variant failing the formal gate is now a documented finding — carried into [`10_behavioral_trade_update.md`](10_behavioral_trade_update.md) §3 as LeanBroth's SR-GS-002 failure and loss of its ADR-009 descope-option status — rather than a reason to withhold trade-study results for the variants that do comply. This is a deliberate departure from ADR-011's rationale: ADR-011's blocking behavior was designed to catch *drift* between the formal and procedural compliance paths (a modeling or bookkeeping error), and correctly still hard-errors on any formal/procedural disagreement; it was never intended to withhold an otherwise-sound trade study just because behavioral fidelity revealed a genuine, previously-invisible non-compliance in one variant. The minimum-two-compliant-variant requirement prevents the trade study from degenerating to a single-variant non-comparison if a future update fails a second variant.
