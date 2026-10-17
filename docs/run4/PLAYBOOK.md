# Worker playbook (read fully once)

You control ONE Factorio character in a real-time, multi-agent rocket speedrun. Factorio 2.0.77 WITH Space Age
(quality mod present but ignore quality), random map. Biters exist but are PEACEFUL: they never attack unless
attacked. Never shoot, damage or build turrets near spawners/biters unless the planner assigns it. The win is a
space platform reaching the Solar System Edge; the first stage is the Nauvis base up to rocket silo + platforms. The game clock never pauses: every minute you spend idle or confused
is lost. A planner coordinates (it has no character); several workers like you each own one character.

## How to act
- Only interface: `scripts/fa <your-character> <tool> '<json>' [<tool> '<json>' ...]`, run with the Bash tool
  from `D:/Documents/Codes/llm-play-factorio`. Each call takes several seconds, so chain several tools in one
  call (`scripts/fa iron-1 check_inventory '{}' scan_area '{"radius":12}'`). Use single quotes around JSON.
- Tool reference: `runtime/run/workspace/TOOLS.md` (grep it for the tool you need; don't read it all at once).
- To SEE an area: `scripts/lpf render-area X1 Y1 X2 Y2 [--power]` (max 200x200) renders a schematic PNG
  into runtime/run/workspace/renders/ and prints a legend (positions, recipes, machines with problems);
  open the PNG with the Read tool. `scripts/lpf render-plan plan.json` draws a layout you wrote (JSON list
  of build_plan steps) before you build it; `--plan plan.json --dx N --dy N` on render-area overlays the plan
  on the map and lists missing/wrong/extra entities. Prefer this over long ASCII scans when building.
- Directions are 16-way: 0=N, 4=E, 8=S, 12=W. An inserter's direction is the side it PICKS UP FROM; prefer
  `drop_to` / `pickup_from` when placing inserters.
- A mining drill outputs onto ONE tile: the middle tile of its facing side. Burner drills facing a stone
  furnace (or another drill, or a chest) feed it directly.
- Job tools (walk_to, mine, craft_items, place_entity, build_plan, run_plan, insert_items, ...) queue and
  return at once. Queue a whole phase, then use `job_wait` (or `wait_until`) with `wait_s` up to ~60 to let
  it run instead of re-checking every few seconds. If a job fails, everything queued behind it is cancelled;
  the next result tells you.
- Crafting by hand uses only your own inventory. Items move between characters only through containers or
  machines (insert_items / extract_items), never directly.

## Rules (breaking any of these invalidates the run)
1. No blueprint strings that were not exported from this map during this run. Don't call import_blueprint
   or build_blueprint with a string you wrote or remembered. Placing things with place_entity / build_plan /
   run_plan / route_belt / route_pipe is fine. Writing your own layout code in the workspace is fine.
2. Only the `scripts/fa` CLI touches the game. No RCON, no console commands, no editing game or mod files.
3. No internet. Don't read files outside `runtime/run/workspace/` except running `scripts/fa`.
4. Don't remove or rebuild other characters' buildings unless the planner assigned it.
5. Human players on the server are spectators. Leave their characters and items alone.

## Coordination
- `runtime/run/workspace/board.md` is the planner's task board. Read your section before starting and after
  finishing each task.
- Keep `runtime/run/workspace/status/<your-character>.md` up to date (overwrite it): current task, position,
  what you have spare, what you need. Short.
- Game chat (`say`) is for quick handoffs ("coal chest at (40,-50) has 50 coal"). Unread chat from others
  appears at the end of every tool result.
- When your assignment is done, or you are blocked for more than a couple of minutes, stop and return a short
  report to the planner: what you built (with positions), what's running, inventory surplus, problems.
- `extract` with `"all": true` takes EVERYTHING (fuel and ore too). To collect plates use `"item":"iron-plate"` with a count, never `all`.
- "pathfinder found no path" inside a dense drill/chest cluster: walk_to a nearby open tile first, then to the far target.
- Long walks (>~60 tiles) or walks out of a building cluster can fail with "no path": use run_plan with walk_to waypoints ~40 tiles apart, starting with an open tile next to you.
- Fact (tested on dev server): a mining drill outputs onto the NEAR lane of the belt in front of it (drills west of a north-flowing belt fill its left/west lane). Drills on one side only => the other lane is free for coal.
- Before building anything, read the "Phase 2" section of board.md: planned sites are reserved even before they are built.
- POWER RULE: the boiler coal supply must never depend on electricity alone. Keep a coal reserve chest + burner inserter on the boiler belt (black start).
- After changing anything that feeds labs (or any shared line), check the downstream result a minute later (labs "working", research % moving; consumers fed). A "fix" that rotated lab inserters stalled all research for ~10 min.
- Lab feeding rule: never put two pack types on one lane unless labs can always consume both — a lab missing one pack type stops consuming the other and the shared lane deadlocks.

## Module ownership (learned in run 1)
- You OWN the module the planner assigns: design the layout yourself as code in `runtime/run/workspace/layouts/<module>.py`
  (it prints build_plan JSON), check it with `scripts/lpf render-plan` and a `build_plan` dry run, then build it.
  Then write its interfaces (input/output belts, chests, pipes, with coordinates) into your board.md section.
- Automate inputs with belts/inserters; hand-carry only to bootstrap or to finish a last small batch.
- Before building something new, check whether something that already exists can serve (search the board and the map).
- Diagnose by following the chain upstream: a starved consumer usually means an empty chest or a stopped machine further back.
- Watch your drills: when a patch thins out, report it early so the next outpost is ready in time.
- Pipelines longer than ~320 tiles need a pump. Feed undergrounds head-on (side-loading halves throughput).
- POLE RULE: before removing/moving any electric pole, place its replacement first and check the network is still one piece (labs at the base still powered). A moved pole split the grid at game ~1:20 and stopped the whole base.

## Copying a working module (new in run 3)
- A cell that already works on THIS map (furnace column, science cell, lab row, drill line) can be copied:
  `export_blueprint` over a TIGHT rectangle around just that cell prints `anchor (x, y)`; `build_blueprint` with the
  same string at anchor + (dx, dy) builds the copy as one job (directions, recipes and machine facings are kept; the
  anchor snaps to the grid). This is legal (exported from this map during the run) and much faster than a new script.
- Before building: `import_blueprint` lists the bill; carry the items. After building: connect inputs/outputs, then
  confirm the new machines are "working" before you report.
- Never pass a string you wrote, remembered or edited by hand (rule 1).

## Space Age facts (Nauvis)
- Rocket-silo research needs only red, green and blue packs (1000 x 60 s). The tree to it is ~155k lab-seconds:
  ~4300 red, ~4100 green, ~2650 blue. Labs are the limit once blue runs: aim for 30+ labs.
- A rocket is 50 rocket parts; each part = 1 processing unit + 1 low density structure + 1 rocket fuel.
  Rockets carry cargo to space platforms (that is the whole point now); expect many launches.
- A space platform's whole floor is one electric network: machines there need no poles (poles only for circuit wires). Ship solar panels, not poles.
- Logistic robotics is a prerequisite of the silo (robots matter for space platforms too).
- Trigger techs: steam-power (craft an iron plate), electronics (craft a copper plate), automation-science-pack
  (craft a lab), oil-processing (a powered pumpjack extracts crude), steel-axe (craft steel).
- Each pack type keeps its own lane all the way into the lab row.

## Don't leak production (learned in run 2)
- Remove temporary chests and the inserters feeding them when your task is done. A forgotten inserter into a
  steel chest swallowed ~250 iron plates/min in run 2.
- A "shortage" is usually one broken tile upstream (a missing belt tile starved the boilers): walk the chain first.
- Assembler / chemical plant facing now works in build_plan (give direction + recipe in the same step).

## Lanes, overflow and checks (learned in run 3)
- One item per lane, all the way. Most stalls in run 3 were a foreign item on a lane (steel on a pack lane, sulfur on
  a plastic lane, engines on a circuit belt).
- A belt end that can overflow ends in a dead end or its own consumer; never let it sideload onto another belt.
- After building, every new machine must read "working" and every inserter must have power and an input.
- Replace hand-fed chests with belts as part of the build, not later.
- A change to a shared fluid system needs a check of everything else it feeds (a removed cracker left an outlet-less
  pipe and stopped rocket fuel in run 3).
