# Protocol v6: MCP server ↔ game mod

`ping` returns `protocol_version: 6`. The MCP server refuses to bind when the versions differ.

## Transport

Every call is one RCON command:

```
/silent-command remote.call("factorio_mcp","rpc","<method>","<params as escaped JSON string>")
```

- **Params:** always a JSON **string**; the server escapes `\` and `"`.
- **Replies:** the mod answers on the same RCON response with `rcon.print(json)`.
- **One reply per command:** the client sends one command, then reads packets until the one carrying that command's id; that packet is the whole reply (Factorio 2.0.77 does not split replies — measured up to 1 MB). It never pipelines. Replies can come back out of order while a player is connected, so Agentic-Factorio's sentinel trick (a no-op sent right after each command, whose reply marks the end) is not used: with a player online it returned empty replies for state-changing calls such as `bind`.
- **Errors:** runtime Lua errors outside the mod's `pcall` come back as `Cannot execute command. Error: …` (the bridge reports it as an invalid envelope).

### Envelope

```jsonc
{ "ok": true, "data": { ... } }
{ "ok": false, "error": "human-readable message" }     // Lua file:line prefixes are stripped
{ "ok": true, "data": { ... }, "alerts": "ALERTS: no-power 38 (+38 since your last call)" }  // optional, 0.2.19+
```

**Chunking:** a reply over 3400 bytes is stored mod-side, and the first part comes back as `{ok, chunked: true, id, parts, data}`. The server then fetches parts 2..N with `get_chunk {id, part}`. Stored parts expire after 5 minutes.

### Ambient alerts (0.2.19+)

Every scoped response — success or error — except `heartbeat` carries an optional `alerts` string: a one-line digest of the character's force warning counts (the `map_warnings` classification), delta-based against that character's last-seen counts per surface (`storage.alert_seen`). Steady state carries nothing; the first-ever response on a surface is a silent baseline. `heartbeat` is exempt so the 20-second keepalive never consumes a delta the agent hasn't been shown yet. The counts themselves are shared and cached mod-side for 30 ticks. The client appends the line to every tool result (every tool, inbox or not, and to tool errors), turning any call — walk, scan, placement — into an alert surface. Against mods < 0.2.19 the field is absent and the client stays silent.

**Back-pressure (0.2.20):** `waiting_for_space_in_destination` never triggers the line — it is the expected state while the fleet builds — and rides as a trailing summary count (`..., waiting-for-space-in-destination 132`) only when the line fires for other reasons and the count is nonzero. Every other category fires at `|Δ| >= its threshold`: default `storage.alerts_config.min_delta` (1), per-category overrides in `.by_category`. Tunable at runtime, no mod release: the `/alerts-threshold` console command (server admins / RCON) — no args shows, `N` sets the default, `<category> N` (or `reset`) sets one category.

**Tool gating (client, 0.2.19+):** the MCP server holds back tools whose `TOOL_MIN_MOD` entry exceeds the live server's mod version (learned at bind, or probed characterless via `ping` when tools are listed before a bind; unknown version → everything advertised, as before). A gated tool called anyway fails with an honest version message instead of the mod's `unknown task type` (which now names the running mod version).

## Scoping and binding

Every method except `ping`, `echo`, `get_chunk`, `bind` and the harness RPCs (`register_blueprint`, `list_registered_blueprints`, `area_snapshot`, 0.2.23+, see below) must carry `companion` (the character name) and `session` (the MCP instance's token). The mod checks that this session holds the binding, then refreshes the lease. Calls from anything else fail with `this MCP session does not hold character …`.

| Method | Params | Result |
|---|---|---|
| `bind` | `{name, session, takeover?}` | Claims the character. Refused if another session called within 60 s, unless `takeover: true`. Spawns the body at the force spawn point if missing (freeplay `created_items` kit on first creation). Returns `{name, position, surface, already_existed, took_over, kit?}` |
| `heartbeat` | — | No-op that refreshes the lease. The server sends it every 20 s |
| `unbind` | — | Releases the binding and leaves the body in the world. Sent on shutdown |
| `respawn` | — | New body after death (freeplay `respawn_items` kit) |
| `retire` | — | Removes the character entirely: body with inventory, jobs, binding. Used for test cleanup |

## Perception (instant)

All results are filtered by fog of war (`scripts/vision.lua`):
- **KNOWN:** chunks explored by the force's agent characters (5×5 chunks around each), or charted by the force.
- **VISIBLE:** within 32 tiles of any force member, or in a radar-visible chunk.

| Method | Notes |
|---|---|
| `get_state {radius≤80}` | The character, other agent characters, players, resource patches and trees (known ground), own buildings with status histograms, visible enemies, research, power, top production, `explored_chunks` |
| `check_inventory` | Own inventory and equipment. Keys are `name`, or `name@quality` for non-normal quality |
| `inspect {position} \| {targets≤16}` | Target must be known. Entities of other forces must be visible. The result carries `last_changed` ("what by whom (job #N) at tick T") when a job of this mod last placed, rotated or re-reciped the entity — the fleet shares one force, so that is the audit note for a machine found facing the wrong way |
| `analyze_factory {radius}` | Own machines on known ground, grouped by problem |
| `map_warnings` | Every own-force entity on charted ground with a problem status — the map screen's warning icons — grouped by problem with positions (nearest first, at most 60 per group, `more` counts the rest). Same problem classification as `analyze_factory` |
| `alerts` | The game's alert panel, read through any connected player of the force (in 2.0 alerts live on players; the panel is force-wide information the human player watches). Grouped by alert type with each alert's target/position and the tick it was raised. Headless fallback: `battle_report` |
| `battle_report {recent_s≤600}` | Battlefield snapshot: own-force entities below max health (worst first, at most 30), turrets with an empty ammo inventory, enemy clusters on charted ground (position-clustering; distance to the nearest own-force entity, closest threat first, at most 10), and recent combat events from the event log |
| `scan_area {center?, radius≤120}` | ASCII grid; unknown tiles are `?`. Below the grid: every inserter with its direction and what it picks from / drops into, and every mining drill with the one tile it outputs onto and what stands there (drills with an empty output tile or no minable resources first) |
| `can_place {item, position, direction} \| {placements≤24}` | Position must be known |
| `find_buildable_area {width, height, near, max_distance}` | Known ground only |
| `describe_prototype {names≤10}` | Static prototype data |
| `production_stats {window, names?, kind?, top?}` | Force item and fluid flows on the character's surface. `window` ∈ 5s, 1m, 10m, 1h, 10h, 50h, 250h, 1000h. Returns `produced_per_min`, `consumed_per_min`, `net_per_min` and all-time totals |
| `list_technologies {status?, search?}` | Every technology for the force: internal name (exactly what `start_research` takes), display label, status (researched / in-progress / queued / available / trigger / locked), prerequisites (missing ones named), the total research bill per science pack, and per-unit time at one speed-1 lab (derived as unit energy / 60). `status` filters (default `available` — the unlocked-but-unresearched set), `search` is a name substring; the live research queue in order ([1] = in progress) is always included |
| `list_trains`, `list_blueprints`, `read_blueprint`, `import_blueprint {string}` | Blueprints: only ones the character carries, or export strings. A string must pass the provenance gate (0.2.23+): its layout has to be in the blueprint registry, else the call fails with `this blueprint string is not allowed: the run rules only allow blueprints exported from the map (export_blueprint) or compiled from your own in-run layout…`. Carried blueprints are never gated |
| `export_blueprint {area: [{x,y},{x,y}]}` | Own buildings in a known area of at most 200×200 tiles. Returns `{string, entity_counts, total_entities, size, anchor}`. The layout is registered (source `export`, 0.2.23+) so the string passes the provenance gate |
| `get_chat {since_id}` | Everything after the cursor except this character's own lines. Agent lines have `bot: true`. A line with `to` is delivered only to that character (`all` or no `to` = everyone); a player addresses one with a leading `@w3 ` |
| `get_events {since_id}` | Events for this character plus force-wide ones (`job_done`, `job_failed`, `attacked`, `died`, `research_finished`, `supply_warning`, `under_attack`, `destroyed`, `craft_cancelled`, `rocket_launched`). Combat: character damage is throttled to one `attacked` per 5s; other force entities' damage is aggregated into one force-wide `under_attack` per 5s window (worst first), and a force entity's death pushes `destroyed` immediately with the cause |

| `route_belt {from, to, belt?, allow_underground?, clear_obstacles?, margin?, avoid?, planned_belts?}` | Plans one belt line on known ground (see `scripts/route/`). An endpoint is `{x, y, direction?, port}` with `port` ∈ `tile`, `drop`, `pickup`, `belt` or `fluid` (inserter/drill drop tile, inserter pickup tile, join an existing belt). `allow_underground` nil means: if carried or the recipe is enabled. The search box is the endpoints' bounding box plus `margin` (2–40), at most 160 tiles a side. Returns `steps [{item, x, y, direction, underground_type?}]`, `bill`, `missing`, `unavailable`, `mine_first` (trees and rocks on the path), `effects` (what joining the target belt does), `length`, `turns`, `underground_pairs`, `expansions`. No side effects: the MCP server turns the steps into mine and `build_plan` jobs when `build=true` |
| `route_pipe {…}` | The same for pipes and pipe-to-ground. It never runs next to a foreign fluid connection, so fluids don't mix |

## Harness RPCs (0.2.23+)

Tooling for the run's own harness (blueprint compiler, schematic renderer). They are **unscoped** (no `companion` or `session`, callable like `ping`) and the MCP server has no tool for them, so agents cannot reach them. The Python side is `Bridge.register_blueprint` / `list_registered_blueprints` / `area_snapshot` (also on `Game`, which binds no character for them) and the CLI commands `snapshot`, `register-blueprint` and `blueprint-registry`.

### Blueprint provenance

`import_blueprint {string}` and `build_blueprint` (at enqueue, and again when the job starts) given a `string` refuse a layout that is not in `storage.bp_registry`, unless the runtime-global mod setting `factorio-mcp-enforce-blueprint-provenance` is off (default on). A refused `build_blueprint` is an enqueue error, not a failed job. Carried blueprints (`label`) are not gated.

Registry key: a 128-bit non-cryptographic hash (four multiply-add lanes modulo primes just under 2^32; 32 hex digits) of this canonical text:

```
helpers.table_to_json({1, entity_lines, tile_lines})        // both lists sorted as plain strings
entity line   name|x|y|dir|recipe|type|input_priority|output_priority|filter|quality
tile line     name|x|y
```

- Positions are shifted so the smallest x and the smallest y over the blueprint's entities (over the tiles when there are none) are 0, and written with two decimals (`%.2f`).
- `dir` is `direction` (north when absent); `type` is the underground belt / loader `input` or `output`; `recipe`, the splitter priorities and filter, and `quality` (empty for normal) are empty when absent; tables are flattened with sorted keys.
- Entity numbers, labels, icons, the version, the position on the map and the string's encoding are not part of the key.

| Method | Params | Result |
|---|---|---|
| `register_blueprint` | `{string, source, note?, character?}` | Decodes the string (one blueprint, not a book; at least one entity or tile) and records its layout: `{key_hash, entity_count, already_registered}`. The first registration of a layout wins (`source` up to 64 characters, `note` up to 300) |
| `list_registered_blueprints` | — | `{enforced, total, blueprints: [{key_hash, source, character?, tick, entity_count, note?}]}`, oldest first |

### area_snapshot

`area_snapshot {x1, y1, x2, y2}` (at most 200×200 tiles) is instant and read-only and reports only **explored** ground (`scripts/vision.lua`). It is built for a schematic renderer and replies through the chunked mechanism when large.

```
{ "tick": int, "area": [x1,y1,x2,y2],
  "unexplored_chunks": [[cx,cy],...],        // chunks overlapping the area that are not explored
  "entities": [{ "name", "type", "x", "y", "dir": 0..15, "box": [l,t,r,b], "force",
                 "status"?, "recipe"?, "ug"?: "input"|"output", "pickup"?: [x,y], "drop"?: [x,y],
                 "out"?: [x,y], "ghost"?: true, "label"? }],
  "resources": { "iron-ore": [[x,y,amount],...], ... },   // x,y = tile top-left integers
  "water": [[x,y],...],                                  // tiles that collide with water_tile
  "obstacles": [[l,t,r,b,"tree"|"rock"|"cliff"],...] }
```

- `entities` are all entities on explored ground except resources, trees, rocks (`simple-entity`), cliffs and ground litter (item entities, corpses, effects). Other forces' entities are included with their `force`. They are sorted by y, then x.
- `box` is the world-space `bounding_box` (already rotated); `status` is the key name of `defines.entity_status`; `recipe` is set on crafting machines and furnaces (a furnace's previous recipe when idle); `pickup` / `drop` on inserters; `out` (the drill's `drop_position`) on mining drills; a ghost reports `ghost_name` / `ghost_type` as `name` / `type`; `label` names an agent character.
- Coordinates have two decimals. The game serializes an empty list as `{}`; the Python helper turns those into `[]` and rounds float dust.

## Rocket launch (0.2.24+)

A rocket silo builds a rocket from 100 rocket parts (`LuaEntity.rocket_parts`; `prototype.rocket_parts_required`). The rocket then goes through the `defines.rocket_silo_status` phases up to `rocket_ready`; a silo without power stops in its opening phases.

- **`launch_rocket {target}`** (job): walks within reach of the silo, then
  - no rocket yet: fails at once, `can't launch: no rocket yet: 37/100 rocket parts …`;
  - a rocket on its way up: waits (up to 120 s, then fails naming the phase and the silo status);
  - `rocket_ready`: calls `LuaEntity.launch_rocket()` and waits for the `on_rocket_launched` event (up to 90 s), then reports tick, character and payload.
- **Payload:** `insert` on the silo puts items into the rocket's cargo slot (`defines.inventory.rocket_silo_rocket`, one slot). The slot exists, and takes items, before the rocket does. `extract` takes them out again. The rocket and cargo-pod entities that stand on a silo are skipped when a point is resolved, so the silo is the target.
- **Progress:** `get_state` lists `rocket_silos` on known ground — `{x, y, parts, parts_required, phase, has_rocket, ready, launching, status, cargo}` — and `inspect` of a silo carries the same as `rocket`. Both are shown by the `status` and `inspect_entity` tools.
- **Result:** `on_rocket_launched` records `{tick, seconds, character?, player?, payload, silo, launch_number}` in `storage.rocket.launches`; the first launch is `storage.run_result` (and appears in `get_state` as `rocket_launched`). It also
  - writes `script-output/run-result.json` on the server only (`helpers.write_file` for player 0, overwritten on each launch; it holds the first launch's fields plus `launches` and `mod_version`),
  - prints `ROCKET LAUNCHED at tick … by …, payload: …` to everyone, adds it to the chat log as a `server` line,
  - and pushes a force-wide `rocket_launched` event, so it rides the news footer of every tool result.
  The character is the one whose `launch_rocket` job called the silo within the last 3 minutes; a launch by a human has `player` instead.

## Replay log (0.2.24+)

With the runtime-global setting `factorio-mcp-rpc-log` (default on), `rpc.dispatch` appends every RPC to `script-output/rpc-log/<run-id>.jsonl` on the server (`helpers.write_file`, player 0, append) **before** the handler runs. `run-id` is `run-<map seed>`; `scripts/new_run.sh` wipes `script-output`, so a new run starts a new file.

```
{"header":true,"run_id":"run-4285574714","seed":"4285574714","tick":457,"mod_version":"0.2.24","factorio_version":"2.0.77","log_format":1,"settings":{…every factorio-mcp setting…}}
{"tick":457,"method":"ping","character":null,"params":{}}
{"tick":1273,"method":"enqueue","character":"coal","params":{"task":{…},"request_id":"…","chain":"…","companion":"coal","session":"…"}}
```

- The header opens the file and is written again after each mod version change. `params` is the JSON text the MCP server sent, verbatim. `character` is `params.companion` (or `params.name` for `bind`). Every method is logged, reads included, except `get_chunk`.
- `tick` is `game.tick` inside the RPC.

What a replay runner needs:
- **Start from the same map:** the same seed and map settings, the same mod version and mod settings (the header), and the same save state when the log starts. The log is the *inputs* only; it does not contain the initial save.
- **Order inside a tick (measured on 2.0.77):** an RPC with `tick` T runs *between* ticks: after every `on_tick` / `on_nth_tick` handler of tick T-1 and before those of tick T. A replayer must issue the commands of tick T in file order and only then let tick T run (`game.tick` already reads T inside the command, and the handler of T has not run yet). Several RPCs in the same tick run in the order of the file.
- **Replay all of it:** reads change state. `get_chat` / `get_events` advance read cursors; scoped calls refresh the session lease and update the ALERTS baseline (`storage.alert_seen`); `bind` and `heartbeat` carry the leases. Session tokens are random per MCP process — only their equality matters, so a runner may map them to fresh ones as long as it keeps them consistent. `request_id`s are de-duplicated for 5 minutes of ticks.
- **Rollbacks:** a server restart reloads the last autosave and the log keeps growing, so the file contains the rolled-back stretch too. A record whose `tick` is lower than the one before it starts a new segment; a runner should drop everything from the earlier segment at or after that tick (and a second header marks a mod-version change).
- **Not in the log:** things humans do (chat, `/follow`, joining; humans are spectators and cannot change the map, but their *presence* feeds `vision.is_visible` and `get_state.players`, which agents read), console commands, and the mod's own on_tick work, which is derived from the inputs.
- **Nondeterminism to watch:**
  - the *real-time arrival* of an RPC is nondeterministic, but its tick is recorded, and ticks are all that matter once the commands are replayed at those ticks;
  - pathfinding is asynchronous (`request_path` answers arrive in later ticks, paced by the pathfinder budget in `map_settings`, which the mod writes from the `pathfinder-budget` setting) — deterministic in the engine, but only if that setting and the other agents' simultaneous requests are the same;
  - `pairs` over tables keyed by string (lane order in `tasks.on_tick`, `companion` records) has an order the engine fixes for a given construction history; it is not guaranteed to survive a save/load, so jobs of different characters in one tick could run in another order after a reload (they touch separate characters, but they share the map);
  - `game.tick`-dependent paths: binding lease (`LEASE_TICKS`), `request_id` TTL, chunked reply expiry, chart/ALERTS caches (30 ticks), combat window aggregation (5 s), the 120/300/600-tick housekeeping handlers;
  - no `math.random`, wall-clock or `game.ticks_played` use was found in the mod (`grep` over `scripts/`), and `rendering` / `game.print` affect nothing but display.

## Humans spectate (0.2.24+)

With `factorio-mcp-humans-spectate` (runtime-global, default on), a player who joins (`on_player_joined_game`), every player when the setting is turned on or the mod starts, and any player found with a character by a 5-second sweep, gets `set_controller{type = spectator}`. The character the freeplay scenario gave them is **destroyed** (items and all), so it cannot be used as an item source; the characters of agents are never touched, and neither are players already in remote view (`/follow` uses the remote controller). Offline players are included in the sweep.

## Save archive (0.2.24+)

With `factorio-mcp-archive-minutes` N > 0 (runtime-global, default 10, 0 = off), every N minutes of game time (checked every 10 s) the mod calls `game.server_save("archive-<tick, 9 digits>")`, which writes `saves/archive-<tick>.zip` next to the autosaves (`runtime/factorio/saves/` for the Docker setup). Nothing overwrites these files, so the run's whole history stays on disk. The tick of the last one is `storage.archive.last_tick`.

Measured on the headless 2.0.77 server: `game.server_save` called in the same tick as an autosave is dropped without an error (the autosave runs, the archive never appears), and the two line up whenever the interval is a multiple of the autosave interval (both count from the session start). So each archive is requested twice, one check (10 s) apart, under the same name; if both succeed the second rewrites the file with the state 10 s later. Saves requested outside an autosave tick work from a mod event handler as well as from the console.

## Instant actions

`say {text, to?}`, `post_chat {text, from?, to?}` (unscoped: a supervisor line with no character, used by `scripts/send_chat.py`), `start_research {technology}`, `cancel_research {technology}`, `equip {gun?, ammo?, armor?}`, `exit_vehicle`, `set_train_schedule {train_id, stops}`.

## Jobs

| Method | Params | Result |
|---|---|---|
| `enqueue` | `{task, replace?, quiet?, chain?}` | `{task_id, cancelled?}` |
| `get_task` | `{task_id}` | `{status, detail, type}` for **own** jobs only. Status is one of queued, running, done, failed, cancelled |
| `list_tasks` | `{limit?}` | Own `active`, `queued`, and `recent` (finished within 5 minutes) |
| `cancel` | `{task_id}` or `{all: true}` | Own jobs only; cancelling another character's job raises an error |

Each character has one lane, a FIFO queue plus the active job, and lanes tick in parallel.
- **`replace`** cancels the lane first.
- **`chain`:** when a step of a chain fails, the rest of the chain is cancelled.
- **Restarts:** a server restart rolls the game back to its last autosave — jobs queued after that save are gone, and a chain whose jobs vanished that way never receives its failure (it was annihilated, not failed). The MCP client detects the rollback at the next bind (the server tick is below the last one the character saw), cancels whatever the rolled-back save resurrected in the lane, starts a fresh chain, and tells the agent to resubmit.
- **`quiet`** suppresses the `job_done` event.

Task types:
- movement: `walk_to`, `drive_to`, `follow_player`
- resources and crafting: `mine`, `craft`
- placing and configuring: `place`, `rotate`, `set_recipe`
- inventory transfers: `insert`, `extract`
- ground: `pick_up` — collect item-entities within a `radius` (≤25) of a `target` (default: where the character stands), walking over them into the inventory; characters do not collect by walking past
- building: `build_plan`, `build_blueprint`, `deconstruct`
- the end of the run: `launch_rocket` — `{target: {x, y}}`, a point on the silo (0.2.24+); see "Rocket launch"
- combat and upkeep: `fight`, `defend_area`, `keep_fueled`

Every task with a map target walks within reach first, and each movement goal is checked against the exploration rule.

For inserters — `place` and `rotate` alike — the 16-way direction is the side the inserter PICKS UP FROM: facing north (0) it picks from the north tile and drops south (8 would pick from the south tile and drop north). This is game truth, read back from live entities; it is the opposite of the intuitive pointing-at-the-drop-target reading, and the tool schemas say so at every direction entry point.

### Craft reporting

`craft` jobs follow the engine's queue semantics, and their reports make the accounting visible:
- `count` is recipe executions; a multi-output recipe yields its result per craft (poles: 2 per craft). The done line reports items made — `crafted 2x small-electric-pole -> 4 small-electric-pole (2 per craft)` — plus the net pocket delta when the character used items while it ran.
- Ingredients are counted from what the character carries — chests don't count. A partial start says why: the chain-aware ceiling (`get_craftable_count`, intermediates included) and the directly short items.
- `begin_crafting` auto-queues intermediates (greens queue inserters, circuits, cable…); the start report names the queue depth and the intermediate recipes.
- A queue that makes no progress while the inventory is full fails the job with instructions: completed results are held back until slots free up (the engine holds them in the queue) while started crafts' ingredients are already spent — this is the "half delivered / items vanished" phenomenon, not an inventory desync.
- Cancelling or failing a craft refunds what's queued; a `craft_cancelled` event reports what was already crafted and kept — products and intermediates both. The kept list is the live main-inventory delta against the job's own start snapshot, so after a server restart a resurrected craft job's cancellation can list crafts completed before the save (the items are real — they're in the rolled-back inventory).

### Belt checks

- `trace_belt {position}` follows the line through the belt at `position` both ways, up to 400 tiles each way, on known ground. It goes through turns, undergrounds and splitters. Underground legs carry a `note` on their pairing. A line that stops at an unpaired entrance says why it has no exit (`inspect_entity` returns the same text as `underground`).
  - It returns `{start, tiles, legs, begins, ends, fed_by, taken_by, lane_capacity_per_min}`.
  - Each leg is a run in one direction: `{from, to, tiles, moving, kind?, left, right, left_side, right_side, fill_left, fill_right}`. Lanes are named by the direction of travel, with the compass side they're on.
  - `ends` describes a dead end, a side-load onto another belt, a building the line faces, or unexplored ground.
- Job `measure_belt {target, seconds}` samples the belt every 2 ticks and counts items (by unique id) that arrive on each lane after the first sample. It reports items/min per lane against the capacity (belt speed × 4 items per tile × belt stacking), and whether the belt is flowing, backed up (nothing moved) or empty — "empty" with items still reading says nothing new entered the belt's transport line (lane reads are line-scoped, not tile-wide).
- 2.0 transport lines are read per belt entity, but the internal line a read wraps CAN span multiple tiles (`line_equals` is true across different owners): `get_contents` on any tile of a line returns the line's items — at per-tile lines that is the tile, at multi-tile lines more. `total_segment_length` is a LARGER scope — the segment of this line plus every line directly connected front and back — and is NOT the read scope (fill measured against it once read a 49-tile lab-spine leg at 1% while it held 83%). `trace_belt` counts each line once (fill % against the line's `line_length`; a line carries its items and length through corner legs), `inspect_entity` says a belt read is line-scoped and lists where items actually sit (map positions), `insert_items` onto a belt places items on the target tile's span of the line (raw line positions address the whole line), and `extract_items` takes from anywhere on the line (a dead-end pile can be drained from any tile of its line).

### Map overview

`map_overview {center?, radius≤640}` visits every KNOWN chunk in the square once. It counts resources by name, rocks, trees, water tiles and enemy spawners and worms, then groups each category into 4-connected chunk components. It returns `{known_chunks, total_chunks, groups: [{kind, count, chunks, center, at, area, distance}], more}`, nearest first (at most 60). `at` is a real tile of the patch.

**Starting area:** when an agent character first spawns or binds, the force's explored set gains every chunk within `factorio-mcp-start-area` tiles (default 200) of spawn, the area freeplay charts for a new player.

### Build checks

`layout_context {area: [x1, y1, x2, y2], points: [{x, y}, …]}` returns `{belts: [{x, y, direction, type, name, underground_type?}], drills: [{x, y, name, direction, drop: {x, y}, drop_into, drop_into_type, status}], at: [name | "nothing" | "unexplored"]}`. It's read-only and uses known ground only (at most 200×200 tiles, 400 points).

The server combines it with the plan's own entities (`checks.py`):
- belt dead ends next to an input-less line;
- belts facing each other;
- each inserter's pickup and drop entity, with a warning when it picks from nothing or from a chest placed in the same plan;
- each drill's one output tile (the middle tile of its facing side, next to the footprint — the prototype's `drop_offset` rotated by direction): a warning when neither the plan nor the ground puts a receiver there, for drills the plan places and for existing drills near it. Dead drills (`no_minable_resources`) are skipped: nothing comes out of them.

### Idempotent enqueue

`enqueue {…, request_id}`: the mod remembers each `request_id` for 5 minutes. A repeat (the client retrying after a lost reply) returns the job the first attempt created, with `duplicate: true`. The server sends a fresh `request_id` with every enqueue.

### wait_until

`{type: "wait_until", seconds}`, `{type: "wait_until", item, count, at?}` or `{type: "wait_until", research}`, plus an optional `timeout_s` (default 300). Checked every 30 ticks. It fails with "timed out waiting for …" when the time runs out.

### Optional jobs

`enqueue {…, optional: true}`:
- A failure of this job doesn't mark its chain failed, so later jobs still run. It emits `optional_job_failed` instead of `job_failed`.
- It is still cancelled when an earlier job of its chain fails.

### Queue-ahead (server side)

- **One chain per character.** The MCP server passes one `chain` id with every job of its character: single tools, `run_plan` steps and route builds alike.
- **Failure handling.** When a chained job fails, the mod cancels the queued jobs of that chain and remembers the chain as failed. A late enqueue for that chain is cancelled at once (`{cancelled: true}`).
- **After a failure.** The server starts a new chain as soon as it has told the agent about the failure, by any of:
  - a `job_failed` event in a result footer;
  - a failed or cancelled wait;
  - a cancelled enqueue;
  - `job_cancel all`;
  - `replace=true`.
- **Footers.** Every tool result (except `read_chat`, `wait_for_events` and `status`) ends with the `get_events` and `get_chat` entries since the character's cursors. Reading advances the cursors, so each entry is shown once.

## Fairness rules enforced mod-side

- **Movement:** `request_path` plus `walking_state`, with running-speed modifiers held at 0.
- **Hand mining and deconstruction:** `mining_time / (0.5 × (1 + force bonus + character bonus))`, reach checked. Mined items are recorded in production statistics.
- **Crafting:** only through `begin_crafting`, the real queue with real time.
- **Placement:** build range, `can_place_entity` with the manual build check, and the item is consumed from the character's inventory (with quality).
- **Transfers:** reach checked, and item counts are conserved.
- **Starting items:** only the freeplay scenario's kits.
