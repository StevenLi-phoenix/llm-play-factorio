# Lessons from run 3

Run 3 launched a rocket at game time 8:26:02 (tick 1,821,727). That is 1:59:23 faster than run 2 (10:25:25) and 5:06:59 faster than run 1 (13:33:01). It used about 39 agent-hours: 66 worker stints, all sonnet at medium effort, plus the planner, at most 4 workers at once. Wall time from start to launch was 8:38:53. factorio-mcp was 0.2.26, with the placement fixes for machine facing and blueprint anchors.

Every lesson below is written as a rule to follow. The rules in `lessons-run1.md` and `lessons-run2.md` still hold.

## Where the time went

| Game time | Milestone |
|---|---|
| 0:35 | steam power up |
| ~0:40 | red science automatic |
| ~1:10 | green science automatic |
| 1:47 | oil-processing researched (first pumpjack ran) |
| ~2:45 | blue science reaches the labs |
| ~3:13 | purple science reaches the labs |
| ~4:40 | yellow science reaches the labs |
| ~7:30 | rocket-silo researched |
| 8:26 | launch |

Purple was the critical path from 3:15 to the end. It stopped completely at least four times, and every stop had a small cause: a missing belt tile, a lane plugged with steel, a jammed inserter, engines overflowing onto the advanced-circuit belt, and a module assembler with no advanced-circuit inserter.

## What made run 3 faster

- **The map was scanned at minute 0 and the planner assigned one module per owner from the start.**
- **Oil was found by a dedicated scout** at 445 tiles before oil research was needed.
- **Rocket parts were stockpiled during the research.** At rocket-silo completion the chests held 1005 LDS, 1656 processing units and 898 rocket fuel, so the silo was full 55 minutes later.
- **Copying working cells with export_blueprint + build_blueprint** doubled smelting columns, advanced circuit blocks and purple units in one job each.
- **Fresh agents per stint.** Each stint ended near 200k tokens of context with a handover note in `status/<character>.md`.

## Research

- **oil-processing is a trigger tech in 2.0.** It completes when a powered pumpjack extracts crude, and it cannot be queued. Put the first pumpjack up as soon as oil-gathering is researched.
- **The research queue holds 7 techs and rejects a tech queued before its prerequisite.** Queue prerequisites first and refill the queue every check.
- **Check that research % moves at every planner round.** Two stalls (no purple reaching the labs) were found by the planner, not reported by workers.

## Belts and lanes

- **One item per lane, all the way.** Most stalls came from a foreign item on a lane: steel on the purple lane, copper on coal lanes, sulfur on the plastic lane, engines on the advanced-circuit belt, plastic and sulfur on a cable lane.
- **A belt end that overflows must end in a dead end or a dedicated consumer.** Never let it sideload onto another module's belt.
- **After building, check every new machine reads "working"** and every inserter has power and an input. A missing inserter or one missing belt tile idled a whole block several times.

## Resources

- **Coal ran short around 3:30.** The home coal patch was small. A second coal field 361 tiles away and solid fuel from oil covered it. Plan a second coal source as soon as smelting passes ~100 furnaces.
- **Copper ran short after 5:00.** Advanced circuits, LDS and processing units all draw on copper. Open a second copper field before purple and yellow start.
- **A long crude pipeline needs pumps.** The 420-tile line delivered nothing until 3 pumps went in.

## Organisation

- **Hand-fed chests are a stall waiting to happen.** Replace them with belts as part of the build, not later.
- **Give the critical-path science a watchdog agent** that checks it every few game minutes and fixes stalls at the root.
- **Stop an old agent before a new one takes over its character.** Leftover timers in a finished agent can wake it while the new one is working.
- **A change to a shared fluid system needs a full check of what else it fed.** Removing the light-oil crackers left the heavy-oil cracker's light-oil output with no outlet, which stopped the refineries and rocket fuel near the end.
