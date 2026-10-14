# Lessons from run 1

Run 1 launched a rocket at game time 13:33:01 (tick 2,926,896). It used about 44 agent-hours, with at most 4 worker agents at once. Every layout was written during the run and checked in simulation before it was built.

Every lesson below is written as a rule to follow.

## Organisation

- **Give each agent a module to own.** The owner designs its layout, renders it with `lpf render-area --plan`, dry-runs it with `build_plan`, builds it, and writes its interfaces in `board.md`.
- **The board is the contract.** Agents connect to belts, chests and pipes through the coordinates listed there. Each area has one named owner.
- **Run up to 4 workers at once.** That stays inside the API rate limit and keeps every agent productive.
- **Choose the model to fit the task.** Haiku at low effort handles routine work (keeping labs stocked, hauling, refilling chests) well. Sonnet at medium effort suits routing and diagnosis.
- **Resume agents with SendMessage.** A returning agent keeps its context, so it understands follow-up work quickly.
- **Keep a body only while an agent works.** Park finished agents with `scripts/park_character.py`; the planner works through RCON and scripts only.
- **Track agent time in `agents.tsv`.** Each stint has a start and an end, so the budget can be summed at any moment.

## Diagnosis

- **Measure before acting.** Ten-minute production flow plus each assembler's status and missing ingredient finds the root cause in one query. Read missing fluids from the fluidbox and missing items from the input inventory.
- **Follow the chain upstream.** Yellow science stopped because processing units stopped, which stopped because acid stopped, which stopped because one chest ran out of iron plates. The fix sat at the far end of the chain.
- **Check whether a building already exists before designing a new one.** The acid pipe to the processing-unit block was already in place; refilling its iron chest was the whole fix.
- **Count stock across the whole map before adding production.** At research completion, the map already held enough processing units, low density structures and rocket fuel for the full rocket.
- **Check downstream after every change.** A belt fix is finished once the consumer is shown to be working.

## Factorio mechanics

- **Keep one item type per belt lane.** Lab lanes carry one science pack type each. A belt end stops at a dead end or a dedicated consumer.
- **A drill outputs onto the near lane of its belt.**
- **Keep a black-start reserve for power.** A chest of coal with a burner inserter at the boilers restarts the grid after any outage.
- **Give coal its own source for the boilers.** The dedicated coal outpost kept power stable for the rest of the run.
- **Add a pump on pipelines longer than about 320 tiles.**
- **Feed undergrounds head-on for full throughput.**
- **Move to new ore patches early.** Watch the depleted-drill count and open the next outpost while the current one still runs.
- **Insert straight into the silo once the stock exists.** Hauling directly to the silo turned the last 36 rocket parts into a few minutes of work.

## Tooling

- **Send RCON Lua as one line.** Put the code on a single line and leave comments out.
- **Use `/silent-command __factorio-mcp__`** to reach the mod's storage, for example `storage.companions[name]`.
- **Plan routes with waypoints** when leaving dense building clusters.
- **Take everything with `extract … all`**, then return the fuel you want to keep.
- **Show the current tech's percent in `research.py`** so progress is visible between rounds.

## Planner habits that worked

- **Answer user observations with a quick RCON check**, then hand the fix to an owner agent.
- **Launch the rocket from the planner** once the silo has 100 parts, so the finish line stays under one control point.
- **Write lessons into the PLAYBOOK as they appear**, so every newly started agent begins with them.
