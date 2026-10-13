# Simulator architecture

Three layers, cheapest first. Each answers a different question, and each is legal under the run rules
because it only evaluates layouts or plans that agents write during the run; none of them generates layouts.

## L0: static lint (milliseconds)
Input: layout JSON (build_plan steps) or a decoded in-run blueprint.
Checks: footprint collisions (from the game's own prototype dump), belt continuity and facing, underground
pairing and range, inserter pickup/drop targets, drill output tiles, pole coverage of powered machines.
Where: factorio-mcp `build_plan dry_run` already runs most of these against the live map; `lpf` renders the
same layout (`render-plan`, and `render-area --plan` to diff plan vs map).

## L1: rate model (milliseconds)
Input: a target (item, rate) and the recipe/machine data from `data/game/data-raw-dump.json`.
Output: machines per recipe, raw resource rates, belt lanes, power draw. This is arithmetic over the game's
recipes, not a layout. `lpf rates` (planned) prints it.
Also used by the plan model below to turn "factory state" into production rates.

## L2: plan model, "Sim A" (seconds per rollout)
Discrete-event simulation of a whole run at the level of tasks, not tiles:
- State: inventories per site, machines built (by recipe), research done, power capacity.
- Agents: N characters. Each task (walk, hand-mine, craft, build k entities, deliver) has a duration
  from game data (walk speed, mining/crafting time, reach) plus an LLM decision-latency term sampled
  from the measured distribution of this run's tool-call gaps.
- Machines produce continuously at L1 rates once built and supplied.
- Output: time to each milestone (power, red/green/blue science, oil, silo, launch), per-agent idle ratio,
  agent-hours used.
Use: pick N under N·T ≤ 1000 agent-h; compare build orders; spot the bottleneck resource early.
Calibration: replay this run's KPI log (milestone ticks, per-agent tool-call gaps) and fit the latency term.

## L3: sandbox server, "Sim B" (minutes)
A second Factorio instance (the dev container on RCON 27015) used as a test bench:
- A designer agent registers its in-run layout, builds it there instantly with infinite sources/sinks
  (infinity chests and pipes, editor power), runs the game fast (`game.speed`), and reads production stats.
- Returns measured items/min per output and any stuck machines, plus a schematic render.
- Only layouts registered in the live run may be loaded, so the sandbox can't smuggle in outside designs;
  the sandbox map is reset per run.

## Data flow
```
agent writes layout.json ──► L0 lint + render ──► L3 sandbox measure ──► register_blueprint ──► build in run
planner: target rates ──► L1 rates ──► L2 rollouts (N, build order) ──► board.md assignments
run KPIs (milestones, tool-call gaps) ──► L2 calibration
```
