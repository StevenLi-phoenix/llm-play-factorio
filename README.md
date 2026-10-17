# llm-play-factorio

LLM agents play Factorio 2.0.77 in real time on a random map under fixed rules. Each agent controls one
character through [factorio-mcp](factorio-mcp/) (MCP server / CLI → RCON → Lua mod). A planner agent with no
character coordinates the workers through a shared board.

There are two kinds of run:
- **Base game** (runs 1–3): no Space Age, no enemies. The run ends at the tick the first rocket launches.
- **Space Age** (run 4): Space Age on, biters peaceful. The run ends when a space platform reaches the Solar
  System Edge. A rocket launch is only a step on the way.

## Results
| Run | Mode | Result | Notes |
|---|---|---|---|
| 1 | base | rocket at 13:33:01 game time | [lessons](docs/lessons-run1.md) |
| 2 | base | rocket at 10:25:25 | [lessons](docs/lessons-run2.md) |
| 3 | base | rocket at 8:26:02, ~39 agent-hours | [lessons](docs/lessons-run3.md) |
| 4 | Space Age | paused at ~38:53 game time, before the edge | [lessons](docs/lessons-run4.md), [record](docs/run4/) |

## Rules of a run
- Real time: the game never pauses for agents.
- At most 16 agents (the user may set a lower cap for a run); per run T ≤ 168 h and N·T ≤ 1000 agent-hours.
  Every agent that plays counts, including the planner. The ledger is `runtime/run/agents.tsv`.
- No blueprints from before the run: no blueprint files or strings in the environment at start (prompt
  examples excepted), and no pre-written parameterised layout generators. Agents may write layout code
  during the run, check it, and use blueprints made in the run. The mod refuses blueprint strings that
  were neither exported from the map nor registered from the agent's own in-run layout.
- Belt/pipe routing (`route_belt`, `route_pipe`) is allowed. Hand placement is instant within reach, as
  in vanilla.
- Workers touch the game only through `scripts/fa` (factorio-mcp tools). No console commands, no web.
- The planner reads game state over RCON and may set the research queue there. Every other change to the
  game goes through a worker's `scripts/fa` tools.

## Layout
| Path | What |
|---|---|
| `docker/compose.yml` | dev server (mod bind-mounted from source), ports 34197/udp, RCON 127.0.0.1:27015 |
| `docker/compose.run.yml` | play server for a run (frozen mod copy), ports 34199/udp, RCON 127.0.0.1:27017; `DLC_SPACE_AGE=true` turns Space Age on |
| `docker/config/` | server, map-gen (no enemies / peaceful biters for Space Age, random seed) and map settings templates |
| `factorio-mcp/` | vendored fork (git subtree) of linsyking/factorio-mcp; `route/` is GPL-3.0-or-later |
| `lpf/` | schematic renderer (live area / plan / blueprint → PNG + legend), blueprint codec, simulator |
| `scripts/` | `start_run.sh`, `fa` (agent CLI), `rcon.py`, `research.py`, `kpi.py`, `park_character.py`, `timelapse.py`, `dump_prototypes.sh` |
| `docs/` | lessons per run, Space Age tooling notes, simulator design, run 4 record (playbook, board, ledger) |
| `runtime/` | gitignored: server volumes, run workspace, timelapse frames |
| `data/game/` | gitignored: prototype dump from the pinned image (game data isn't redistributable) |

## Running
```bash
scripts/dump_prototypes.sh                      # once: entity footprints etc. for lpf
scripts/start_run.sh                            # fresh base-game map + frozen mod + empty workspace, starts the play server
DLC_SPACE_AGE=true scripts/start_run.sh         # the same for a Space Age run
scripts/fa planner status '{}'                  # act as a character
uv run --directory lpf lpf render-area -40 -40 40 40   # schematic of a live area (needs FACTORIO_RCON_*)
```
To resume a stopped run, start the same container again (`DLC_SPACE_AGE=true docker compose -f
docker/compose.run.yml start`). It loads `runtime/run/factorio/saves/llm-run.zip`.

To watch, join `localhost:34199` with a 2.0.77 client that has `dist/factorio-mcp_<version>.zip` in its
mods folder, and the Space Age mods set to match the run.

## Recording
Headless Factorio cannot create replay-enabled saves, so vanilla replays aren't used. Instead:
- `scripts/timelapse.py` renders schematic frames of the base and encodes them with ffmpeg.
- The mod writes `saves/archive-<tick>.zip` every 10 game minutes and logs every RPC to
  `script-output/rpc-log/`.
