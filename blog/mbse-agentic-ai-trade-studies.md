# Architecture Trade Studies with Agentic AI: Return of the Intergalactic Vegan Soup Factory

*Today's post is once again from guest blogger Sarah Dagen of MathWorks Consulting Services. Back in April, Sarah showed us how she used an AI coding agent to bootstrap a model-based systems engineering workflow. She's back, and this time the soup factory means business.*

---

In [my previous post](https://blogs.mathworks.com/simulink/2026/04/26/model-based-systems-engineering-and-agentic-ai), I used an agentic AI workflow to do some initial system design for an intergalactic vegan soup factory. That first pass followed an RFLP methodology and produced a single design. A single design is an answer without a question. The discipline for asking the question properly is [decision management](https://sebokwiki.org/wiki/Decision_Management): frame the decision, develop objectives and measures, generate alternatives that genuinely span the objective space, evaluate them, check how sensitive the evaluation is to what you assumed, and only then recommend.

This post is that process run end to end on the soup factory, with an agent doing the labor, plus the beat the textbook only gestures at: when we raised the fidelity of the evidence from static roll-ups to behavioral simulation, one of the study's founding assumptions did not survive.

## Framing the decision

The decision statement: select a baseline physical architecture for a facility that cooks at least 8 soup varieties at 200 bowls per hour, ships them across the galaxy by rocket, runs with at most 5 crew, operates from 0.1 g to 12 g, and fits inside hard caps on mass, power, cost, and volume. The requirement set (15 stakeholder needs, 28 system requirements) lives in Requirements Toolbox, with a functional layer of twelve verb-phrase functions and a logical layer of twelve solution roles built on top in System Composer, everything traced.

The evaluation measures come from where the requirements leave room to be better than merely compliant: throughput margin, resource margin, cost margin, automation level, crew margin, availability, and N-1 throughput retention. Seven criteria, every one computable from the models. That last property matters most at the end of this post, because a criterion you compute is a criterion you can recompute when better evidence shows up.

## Three alternatives, three corners of the requirement space

The classic trade-study failure mode is one design wearing three coats of paint. To make the decision worth analyzing, each alternative is anchored to a different fundamental objective, so the set spans the objective space instead of clustering in one corner of it:

| Alternative | Built to maximize | Driving requirements | Design concept |
|---|---|---|---|
| **HyperCook** | Throughput margin | SR-GS-002: ≥ 200 bowls/hour | Four parallel continuous cook lines rated at 320 bph, 60% above the floor |
| **LeanBroth** | Resource-budget margin | SR-GS-011 to -014: hard caps on mass, power, cost, and volume | Two batch kettles, one prep station, more crew in the loop; roughly half of every budget unspent |
| **EverSimmer** | Mission assurance | SR-GS-026: no production halt from any single fault; SR-GS-003: automation ≥ 0.8 | Three independent production cells, each a complete prep-cook-QC-pack chain |

![HyperCook at a glance: parallel everywhere until the flow funnels through single-string QC and packaging](images/variant_schematic_hypercook.png)

![LeanBroth at a glance: modest parallelism with a single-string prep station as the weak link](images/variant_schematic_leanbroth.png)

![EverSimmer at a glance: three independent cells, no single string anywhere](images/variant_schematic_eversimmer.png)

The production cell is my favorite part of the set: a composite component with a miniature production chain inside, which System Composer's hierarchy handles naturally.

![Inside an EverSimmer production cell](images/EverSimmer_ProductionCell.png)

One structural decision worth pausing on: these are three separate architecture models sharing one interface dictionary and one stereotype profile, not variant components inside a single model. The alternatives differ in topology, hierarchy depth, and component count, and each needs its own allocation set and roll-up. That reasoning, like every decision of consequence in the project, went into an ADR-style decision log, which remains the single most useful artifact for picking work back up weeks later.

## Deterministic analysis

Every component in every variant carries the same eleven-property stereotype (mass, power, cost, throughput capacity, MTBF, and so on), so one PostOrder roll-up function works everywhere, nested cells included. Throughput resisted the roll-up, because it is a bottleneck problem rather than a sum: a chain runs at its slowest stage and parallel units add. Each variant's stage topology therefore lives in a small table. The budget caps are parsed out of the requirement text at analysis time rather than hard-coded, so a requirements change propagates with zero code edits.

At this point in the story, all three alternatives pass all eight requirement gates, which stops being surprising once you realize a trade study where two alternatives fail outright is a victory lap, not a study. The information is in the margins: HyperCook passes power at 99.6% of budget, LeanBroth passes automation at exactly the 0.8 floor, EverSimmer is comfortable everywhere except a 4.7% cost margin. (The charts in this section render the study's latest numbers; by the end of this post a requirements ruling will have pushed HyperCook past the cost and volume caps, and you can already see it in the bars.)

![Budget utilization against the requirement caps](images/budget_utilization.png)

Scoring is standard multiobjective decision analysis: score each alternative per criterion, normalize, weight, sum. The method's real value is being forced to state criteria and weights out loud, since weights are where opinion enters. We scored the seven criteria under four named stakeholder weightings, and then, because four hand-picked weight vectors are still four opinions, drew 5,000 random weightings and counted wins: sensitivity analysis over the entire space of plausible stakeholder priorities rather than a few excursions.

![Scores under the four weighting scenarios](images/scenario_scores.png)

![Monte Carlo win share over 5,000 random weightings](images/mc_winshare.png)

EverSimmer takes three of four scenarios, losing only the cost-weighted one to LeanBroth, and wins 85% of the random weightings. That turns "the committee picked EverSimmer" into "EverSimmer is robust to whatever the committee thinks," which is the strongest sentence a deterministic trade study can produce.

By the book, the study could have ended there: alternatives evaluated, sensitivity checked, recommendation written. But every number in it was a rated capacity, a property someone typed into a stereotype. The whole evaluation rested on the assumption that the factory delivers what its components are rated for: lossless flow, no downtime, nothing ever heats up or breaks. That is exactly the kind of assumption a fidelity ladder exists to test.

## Raising the fidelity of the evidence

The next ask to the agent: behavioral models in Simulink, Stateflow, and Simscape, and a rerun of the trade on simulated numbers instead of rated ones.

The part that changed my mind about where simulation should live: a separate plant model duplicates topology the architecture connectors already encode, so every component got an inline behavior inside the System Composer model, wired to its existing ports. The architecture *is* the simulation. My favorite component is the batch cook vat: a Stateflow chart sequences Fill-Heat-Simmer-Drain and drives a small Simscape thermal network. Nobody types in a throughput number; it emerges from batch size and physics.

![The batch cook vat: Stateflow sequencer driving a Simscape thermal network](images/beh_cookvat_model.png)

Simulation immediately produced texture the roll-ups never could: HyperCook ships its first bowl 119 seconds after cold start, the batch variants take about 57 minutes, and an early run silently lost most of a 40-bowl batch as it drained into a rate-limited QC station. Real plants put surge tanks between batch and continuous stages; now so do we.

![Simulated cold start and steady state for all three variants](images/behavioral_throughput.png)

## The assumption that did not hold

Here is the twist: with yield loss and calibration downtime in the model, LeanBroth produces 196.8 bowls per hour against a floor of 200. Its comfortable static margin was an artifact of lossless flow. The compliance gate flags exactly that check, and under the rule we had already set (a non-compliant alternative has no business being scored), LeanBroth drops out of the evaluated set. EverSimmer takes every scenario and 98.4% of the Monte Carlo draws.

Note what actually failed. Not the design, and not the trade study: the *assumption* that rated capacity equals delivered capacity. LeanBroth was compliant under that assumption and is not compliant without it, and no amount of weight sensitivity analysis could have caught it, because every weighting was scoring the same fictional number.

The fault-injection runs corrected a second belief the same way. At two hours in, each variant loses its worst single component: HyperCook and LeanBroth collapse to zero, EverSimmer reports Degraded and settles at 67%. We had claimed that retention number in a spreadsheet for months; now there is a time history of it. The runs also revealed that HyperCook's single string is its QC scanner, not the conveyor we had assumed, because the architecture never put a conveyor on the material path.

![Worst-case single-fault response: two variants collapse, one degrades](images/behavioral_fault.png)

Honest caveats: the reject fractions and calibration schedules are my engineering estimates, and a better QC bench puts LeanBroth back over the floor. The behavioral layer also produced new discriminators the static study never had, like energy per bowl (LeanBroth best, HyperCook worst). More fidelity doesn't just check old numbers; it generates new arguments.

## From a point verdict to a probability

That "engineering estimates" caveat nagged at me, because the Monte Carlo above only varies *opinions*: 5,000 stakeholder weightings re-scoring the same fixed metrics. LeanBroth's verdict was hanging on parameters I had guessed, which is precisely the situation where decision management tells you to assess the impact of uncertainty before you communicate a recommendation.

So the next ask was a second Monte Carlo over the parameters themselves: 200 draws of each variant's QC reject fraction and calibration schedule (right-skewed distributions, because rejects and maintenance overruns have long bad tails), all three variants experiencing the same draw each time so the comparison stays fair. That is 600 actual simulations of the architecture models, dispatched through parsim in about 35 minutes.

![Throughput distributions from 600 simulations against the requirement floor](images/uncertainty_throughput.png)

The result turns the point verdict into a probability: LeanBroth misses the 200 bowls-per-hour floor in 96% of parameter worlds, and even its 95th-percentile world reaches only 199.7. "LeanBroth fails the throughput requirement with 96% confidence over the stated parameter uncertainty" is both a stronger and a fairer claim than "196.8 at nominal," because the remaining 4% quantifies exactly the better-QC-bench scenario the caveat could only gesture at. And with the compliance gate applied per draw and 25 random weightings scoring each world, EverSimmer takes 97.8% of 5,000 worlds uncertain in both physics and priorities. The verdict is robust to what we don't know, in both of the ways we don't know it.

## Where the fidelity ladder led next

The rest of the project applied the same pattern to every requirement that was implemented on paper but exercised by nothing: wire in physics that changes nothing at nominal, sweep the design space, and attach Verify links only where a passing test honestly means met. Two findings deserve their place in this story.

First, the gravity requirement. Every variant carries a gravity-compensation component; no analysis had ever asked it to compensate. A sweep across the required 0.1 g to 12 g range showed EverSimmer, the trade winner, delivering 189 bowls per hour in microgravity, because slow-draining batch vats are exactly the wrong technology for 0.1 g. Only HyperCook holds the floor across the whole range, so only HyperCook earned Verify links to that requirement; EverSimmer's shortfall is a labeled regression baseline and a redesign flag (pump-assisted drains).

![Throughput across the required gravity range, 0.1 g to 12 g](images/gravity_throughput.png)

Second, storage endurance. The facility held 4 to 6 hours of ingredients against a required 72, with compliance priced at 8 to 12 tonnes against a 15-tonne mass budget: a genuine requirements conflict, sent back to its owner with numbers attached. The owner's ruling excluded consumables from the mass budget, the stores were resized, and then the bill arrived: racks for 20,000 bowls still weigh, cost, and occupy, and HyperCook's razor-thin margins could not pay. It dropped out of compliance entirely, leaving EverSimmer the only alternative standing and the trade study a documented forced selection. Resolving one requirement moved the non-compliance somewhere else, and the models watched it happen end to end.

All of it is held by a test suite that grew to 72 tests, with every number in this post held as a regression baseline (superseded ones retained as labeled what-ifs) and requirements coverage reported per candidate architecture: nine of 28 requirements verified by executed simulation for EverSimmer, eight for HyperCook, two for LeanBroth. Per candidate, because an aggregate across three mutually exclusive designs proved worse than no status at all: it showed the gravity requirement verified while the trade winner was exactly the variant failing it.

## Working with the agent, this time

My April post described a propose-approve-generate-run-confirm loop, with me in the middle of every step. That is not how this project went. With the current generation of agent I described outcomes, and it worked in long autonomous stretches: building models, running simulations, writing and executing its own tests, and committing when things were green. My involvement moved up a level, from approving steps to reviewing artifacts and making the calls that were genuinely mine: choosing the variant philosophies, deciding what a Verify link is allowed to assert, insisting the diagrams be readable.

A few observations from that mode of working:

**The agent's tests catch the agent.** The regression baselines flagged the agent's own stale numbers within minutes of existing. When the agent works autonomously, self-built verification isn't a nice-to-have; it's the thing that makes autonomy safe.

**Standing preferences beat repeated corrections.** I told it once that I use "regression baseline," not other jargon, and once that em dashes are banned from my posts. Both became durable memory, enforced across every artifact since, including this one.

**You still take the wheel, just less often and higher up.** The verification-status mystery that stumped the agent's headless debugging was cracked by one interactive experiment I ran in the Test Manager in under a minute. Knowing when a human hand is the cheaper instrument is still an engineering skill.

**Make it write everything down.** The decision log, the gotcha files, the skills it maintains for itself: the agent that documents its own wrong turns doesn't repeat them, and neither do I.

## So what's the point?

Decision management is not a new idea; what has always been expensive is doing it honestly. Genuinely distinct alternatives cost architecture work, sensitivity analysis costs tooling, and raising the fidelity of the evidence costs a simulation effort, so those steps get skipped and the decision matrix gets filled in from datasheets and hope. The agent made each rung of that ladder a follow-up request instead of a program phase: three full architectures with allocation and traceability, scoring checked against 5,000 weightings, then behavioral models that overturned a compliance verdict the static numbers had certified. When raising the fidelity of your evidence is cheap, you find out a margin was fictional while it's still a design decision instead of a program review. The engineering judgment didn't go anywhere; it just got to spend its time on judgment.

## Now it's your turn

The full project (architectures with inline behavior, the component library, requirements, analysis, tests, and all thirty-five ADRs) is in the repo linked below, along with the skills from the first post. Clone it, run runFullAnalysis, run runAllTests, and check my math. Then tell your agent you want a fourth variant and see what it proposes.

Have you tried running an architecture trade study with an AI agent in the loop? Where did it help, and where did you have to take the wheel? Let us know in the comments.
