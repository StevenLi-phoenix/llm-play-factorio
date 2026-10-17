# Lessons from run 4 (Space Age)

Run 4 was the first Space Age run: Factorio 2.0.77 with Space Age, peaceful biters, random map. The win is a space
platform reaching the Solar System Edge. The run was paused at tick ~8.40M (game time ~38:53) and stopped there, before
the edge. The first rocket flew at 4:26:21 (tick 958,917), four hours earlier than run 3's base-game rocket (8:26:02).
Ships reached Vulcanus, Fulgora and Gleba, and all three of their science packs (metallurgic, electromagnetic,
agricultural) reached Nauvis.

Scale: 335 worker stints, almost all sonnet at medium effort, plus the planner. Wall time from start to pause was
41:25 (2026-10-15T04:49Z to 2026-10-16T22:14Z). The user changed the agent cap during the run; it was 6 at the end.
factorio-mcp went from 0.2.26 to 0.3.12 during the run (13 new tools; see `space-tooling.md`). The ledger's end
times are incomplete, so the run has no exact agent-hour total.

The record is in `docs/run4/`: the worker playbook, the planner's board, the agent ledger and `run-result.json`
(all 145 rocket launches with tick, silo, rider and cargo). Every lesson below is written as a rule to follow. The
rules in the earlier lessons files still hold.

## Where the time went

Times are from the mod's RPC log (the first time a worker set each recipe or schedule) and from the launch ticks
in `run-result.json`. A recipe's first setting marks when its line was being built.

| Game time | Milestone |
|---|---|
| 0:20 | red science recipe set |
| 0:46 | green science |
| 1:49 | blue science |
| 4:13 | rocket silo crafted |
| 4:26 | first rocket (tick 958,917); platform alpha (ordered at 4:15) exists over Nauvis |
| 5:06 | space science on a platform; landing pad (38,-58) brings it down |
| 8:03 | alpha leaves for Vulcanus (both thrusters were shot off on the way; it coasted in) |
| 10:12 | production (purple) science |
| 12:49 | metallurgic science on Vulcanus (foundry at 11:56) |
| 14:08 | utility (yellow) science; military science 14:15 |
| 16:07 | first rocket from the Vulcanus silo |
| 18:00 | first ship scheduled to Fulgora; first Fulgora rocket 18:14 |
| 20:37 | electromagnetic science on Fulgora |
| 22:38 | first ship scheduled to Gleba; first Gleba rocket 24:33 |
| 24:34 | agricultural science; egg chamber 24:53 |
| 27:51 | first agricultural packs rocketed off Gleba (28 packs) |
| ~34:40 | platforms eta and zeta destroyed; gamma is the only ship left |
| 36:53 | 276 electromagnetic packs rocketed from Fulgora to gamma |
| 38:53 | pause |

Rocket count: 130 launches from Nauvis, 7 from Gleba, 6 from Vulcanus, 2 from Fulgora. 120 carried a rider.

## Where it stopped

- **Ships.** Seven platforms were built (alpha, beta, gamma, delta, epsilon, zeta, eta). All but gamma were destroyed
  by asteroids. Gamma is parked over Nauvis with 17 belt-fed gun turrets and full thrusters. Its fuel and oxidizer
  crushers have no collector, so their chunk loops die out; give each crusher a collector before gamma flies.
- **Science.** Nauvis makes production science (~12/min) and utility science (18/min when fed). The landing pad holds
  3174 metallurgic, 2644 space and 244 electromagnetic packs. Fulgora makes ~3.6 EM/min. Gleba makes no
  agricultural packs: the egg loop died.
- **Path to the edge.** Promethium science needs biter-egg-handling, fusion-reactor, quantum-processor (cryogenic
  science, so Aquilo) and planet-discovery-aquilo. Every step on that path needs agricultural packs, about 7500 in all.
  Gleba was the bottleneck at the pause.

## Ships

- **Arm every platform before it leaves and before it parks.** Paused and parked platforms are hit by asteroids too.
  Solar panels go first, then the hub. Six ships were lost: unarmed, out of ammo, or guarded only at the front.
  Gamma survived with 17 gun turrets on the front and both sides, fed by a belt from the hub.
- **Keep crusher products out of the hub.** Feed each crusher straight into the plant that uses it (carbon to fuel,
  iron ore to oxidizer, ice to the water plant). A full hub stops the crushers, stops deconstruction, and leaves the
  ship with no water, so no fuel or oxidizer: gamma sat at Fulgora unable to leave for that reason.
- **Give every crusher a collector.** A crushing recipe returns its chunk only 20% of the time. Inserters cannot load
  chunks into a collector, so the loop is collector → crusher.
- **Test a ship parked for 10 minutes before it flies.** Check thrusters full, every turret "working" with ammo,
  no damaged tiles, and free hub slots.
- **Lay platform floor outward in blocks.** A lone foundation ghost with no floor north or south of it never builds.
  A building ghost that never builds usually has an old entity in the way.
- **Ride with the cargo.** A character's pocket is not weight-limited on a rocket, the rocket's cargo is. Riders
  carried most of the build kits. Keep hub slots free before a rider or cargo arrives; items that do not fit are lost.

## Planets

- **Vulcanus worked once foundries ran on lava.** Separate foundries per recipe and big mining drills on tungsten
  took metallurgic science to ~28/min. The first tungsten came from big volcanic rocks by hand.
- **Fulgora needs a plan for junk before scale.** Holmium is under 1% of scrap. The scrap recyclers' junk filled every
  chest and stopped the line until sink recyclers went in. The silo stood on another island, across oil ocean that
  landfill cannot cover, so export ran through a robot link and then a rocket. Build the junk sink and the export route with the first
  recyclers.
- **On Gleba, keep the egg loop powered through the night.** Eggs spoil in 15 minutes and nutrients in 5. A night
  power outage stopped the nutrient loop and every egg died. Give the loop accumulators and a spoilage sink on every
  biochamber output before the first egg arrives.
- **Build the Gleba pack factory at the fruit.** Fruit spoils in an hour and does not travel well; packs and bioflux
  do. One pack takes about 10 yumako and 0.75 jellynut, so 10 packs/min needs 6–8 towers.
- **Hunt eggs with turrets, not by hand.** 21 gun turrets with piercing ammo, loaded from the far side of a small
  nest, killed the spawner and gave 12 eggs with no death. Characters that fought stompers by hand died. Avoid nests
  with strafers; they outrange gun turrets.

## Nauvis

- **Purple and utility stalled on one missing input at a time,** as in run 3: no circuits in the module chest,
  advanced circuits on the processing-unit lane, a side-loaded underground blocking a coal lane, hand-fed engines.
  Measure each science over a 10-minute window before calling a shortage, and follow the chain upstream.
- **Feed silos with inserters.** Robots do not load rocket cargo. A belt and an inserter into the silo fed ammo
  to the ships.
- **Keep shared stock chests for their line.** A worker who takes items from another line's chest must say so on the
  board; taking 1100 circuits from purple line 1's module chest starved it.

## Organisation

- **The planner changes the game only through workers.** The planner reads by RCON and may set the research queue.
  In run 4 it also deleted items from a hub and set filters, schedules and pad requests by RCON. That broke the run
  rules, and the user called it out. Every other change goes through a worker's `scripts/fa` tools.
- **Size jobs to one stint.** About 30 jobs ended at the token limit mid-build. Jobs that measured first and built a
  single fix finished. Give each job one target and the measurement that shows it is done.
- **Plan around the API session window.** All five running workers failed at once when the five-hour limit hit.
  Keep handover notes current so fresh workers can pick up after the reset.
- **Write layout and plan files only in your own workspace files.** A worker ran another worker's stale `/tmp` plan
  and placed poles on the wrong planet.
- **Name the buildings when deconstructing an area.** Area sweeps took down neighbours' buildings until mod 0.3.10
  made `names` required.
