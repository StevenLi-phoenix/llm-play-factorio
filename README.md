# llm-play-factorio

LLM agents play Factorio 2.0 (base game, no Space Age, no enemies, random map) in real time and try to
launch a rocket under fixed rules. Each agent controls one character through
[factorio-mcp](factorio-mcp/) (MCP server / CLI → RCON → Lua mod).

## Rules of a run
- Real time: the game never pauses for agents.
- At most 16 agents; per run T ≤ 168 h and N·T ≤ 1000 agent-hours. Every agent that plays counts,
  including the planner. The ledger is `runtime/run/agents.tsv`.
- No blueprints from before the run: no blueprint files or strings in the environment at start (prompt
  examples excepted), and no pre-written parameterised layout generators. Agents may write layout code
  during the run, check it, and use blueprints made in the run. The mod refuses blueprint strings that
  were neither exported from the map nor registered from the agent's own in-run layout.
- Belt/pipe routing (`route_belt`, `route_pipe`) is allowed. Hand placement is instant within reach, as
  in vanilla.
- Agents touch the game only through `scripts/fa` (factorio-mcp tools). No console commands, no web.
- The run ends at the tick the rocket launches; the payload doesn't matter.

## Layout
| Path | What |
|---|---|
| `docker/compose.yml` | dev server (mod bind-mounted from source), ports 34197/udp, RCON 127.0.0.1:27015 |
| `docker/compose.run.yml` | play server for a run (frozen mod copy), ports 34199/udp, RCON 127.0.0.1:27017 |
| `docker/config/` | server, map-gen (no enemies, random seed) and map settings templates |
| `factorio-mcp/` | vendored fork (git subtree) of linsyking/factorio-mcp; `route/` is GPL-3.0-or-later |
| `lpf/` | schematic renderer (live area / plan / blueprint → PNG + legend), blueprint codec |
| `scripts/` | `start_run.sh`, `fa` (agent CLI), `rcon.py`, `timelapse.py`, `dump_prototypes.sh` |
| `runtime/` | gitignored: server volumes, run workspace, timelapse frames |
| `data/game/` | gitignored: prototype dump from the pinned image (game data isn't redistributable) |

## Running
```bash
scripts/dump_prototypes.sh          # once: entity footprints etc. for lpf
scripts/start_run.sh                # fresh map + frozen mod + empty workspace, starts the play server
scripts/fa planner status '{}'      # act as a character
uv run --directory lpf lpf render-area -40 -40 40 40   # schematic of a live area (needs FACTORIO_RCON_*)
```
To watch, join `localhost:34199` with a 2.0.77 client that has `dist/factorio-mcp_<version>.zip` in its
mods folder and the Space Age mods disabled.

## Recording
Headless Factorio cannot create replay-enabled saves, so vanilla replays aren't used. Instead:
`scripts/timelapse.py` renders schematic frames of the base and encodes them with ffmpeg.
