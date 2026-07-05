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
