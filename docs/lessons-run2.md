# Lessons from run 2

Run 2 launched a rocket at game time 10:25:25 (tick 2,251,542), 3:07:36 faster than run 1. It used about 42.6 agent-hours: 34 worker stints (4 haiku, 30 sonnet) plus the planner, at most 4 workers at once. Wall time from unpause to launch was 10:44:31.

Every lesson below is written as a rule to follow. The run-1 rules in `lessons-run1.md` still hold.

## Where the time went

| Game time | Milestone |
|---|---|
| 0:44 | electric-mining-drill researched |
| ~1:45 | burner phase over, all four ores mined electrically |
| ~2:15 | red and green science automatic |
| ~5:10 | purple science running |
| ~7:05 | yellow science running, rocket-silo research starts |
| ~9:45 | rocket-silo researched |
| 10:25 | launch |

Rocket-silo research alone took about 2.6 game hours, a quarter of the run. It needs 1000 units × 60 s = 60,000 lab-seconds, which works out to about 6 labs' worth of throughput over that time. The labs were starved of packs: yellow ran at about 15/min and purple at about 20/min only near the end.

The whole tech tree up to the rocket silo is 224,425 lab-seconds (44 techs). With 10 labs that is 6.2 hours of research. With 20 labs it is 3.1 hours.

## Research throughput

- **Size the last tech first.** The silo needs 1000 of each of the five packs. Finishing it in 40 minutes takes 25 labs and 25 packs/min of every type. Plan purple and yellow lines for that rate from the start.
- **Build labs in step with science.** Aim for 20+ labs by the time blue science runs. Every tech after that is lab-bound.
- **Feed new labs from the main pack lines.** A splitter that sent packs to old labs left the new lab row empty.
- **Check research % once per round.** A flat percentage means a starved lab row. Fix that before any new construction.

## Copying proven modules

- **Copy a working cell with `export_blueprint` + `build_blueprint`.** A smelting column, a science cell or a lab row that already works on the map can be exported (legal: exported from this map during the run) and rebuilt with an offset. That is one job instead of a new layout script.
- **Use the export anchor.** `export_blueprint` prints `anchor (x, y)`; building at that anchor rebuilds in place, so add the offset you want. The anchor snaps to the print's tile grid. Directions and recipes (including fluid-recipe facings) are kept since factorio-mcp 0.2.26.
- **Export only the cell.** Keep the selection tight: anything else inside the rectangle comes with it, and it shifts the anchor.
- **Copy, then connect.** After a copy, wire its inputs and outputs and confirm the new machines are working before reporting done.

## Diagnosis that paid off

- **Find where the production goes as well as how much is made.** A forgotten inserter into a steel chest swallowed about 250 iron plates/min.
- **Walk the belt upstream.** A coal "shortage" at the boilers was one missing belt tile.
- **Check `electric_network_id` when part of the base goes dark.** A moved pole left a 10.6-tile gap and split the grid into two networks.
- **Keep status scripts read-only.** `research.py` only changes the queue with `--set`.

## Organisation

- **Count stock across the map before the silo goes down.** Hauling processing units, low density structures and rocket fuel straight into the silo turned the end into about 40 minutes.
- **Stop research consumption that competes with the rocket** once the silo tech is done (processing units for modules, for example).
