# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased] - 2026-11-14

### Changed
- `MAX_TOKENS` env: `none` (or `max`) sends no `max_tokens`, so each reply may use the model's own maximum; a number caps it (default 6000 workers / 4000 coach). `factorio-agents.service` sets `none`: a design task had a 6000-token reply cut before its tool call (99 s of reasoning, nothing done).
- Worker prompt asks for rectangular reusable modules (export_blueprint once, then build_blueprint copies) and one finished mining site per ore patch: the human found agents never reuse a layout and scatter half-built mining sites.
- Worker prompt asks for tidy builds (straight rows, parallel belts, 2-tile walkways, no walls around a character, one owner per area) after the human found the base messy; `state/directives.md` carries the cleanup of 143 unbuilt ghosts and 57 empty chests.
- `factorio-agents.service` runs the game at `GAME_SPEED=1` (was 2): a human player is in the game, and the runner re-applied 2 within a minute of every manual `game.speed = 1`.
- The coach's KPI input lists the science packs each queued tech needs (`research-speed-3 [automation+logistic+chemical]`): the 02:19Z board claimed research-speed-3 needs production and utility packs and told w2 to dequeue it, which was wrong (it needs red, green and blue).
- A failed `drive_to` that got stuck tells the agent to `exit_vehicle` and `walk_to` (w4 retried `drive_to` 8 times in 2 minutes from one stuck spot); an over-long tool result is cut on whole lines and names the omitted chars (7% of single-call turns hit the 5.5k cap, a scan grid with a half row read as data); `trace_belt` text says "a transport line" instead of "a 2.0 transport line".
- agent.py: tool timeout, notes/status/tool_help caps and the context-elision thresholds are named constants (no behaviour change).
- Tool results carry one ALERTS line instead of one per RCON call (306 of 2437 logged results had 2+, repeating the counters with stale deltas), and the events footer no longer repeats a `job_done` the result already states ("Job #N done" plus "[event job_done] job #N" was sent twice); failures always stay.
- The per-turn log line now ends in `calls=N results=Mc` (tool calls in the turn, total result chars) so token cost per call chain can be measured from `state/logs`.

### Added
- Live agent output on the dashboard: each agent appends every thought, message, tool call and result to `state/stream/<name>.jsonl` (`stream.py`), and the new `GET /stream` Server-Sent Events endpoint pushes the last 80 events, then each new one within ~0.4 s (`?agent=w1`, `?n=`); the page has an "Agent output (live)" card with per-agent tabs, a thinking toggle and follow-scroll.
- `ghost_build` / `ghost_clear` tools (mod 0.3.14): an agent shows a design as blueprint ghosts (blue previews) on the ground it stands on, nothing built or crafted, each step checked and rejects listed; before this only space platforms had ghosts, so a design could only be shown by building it. Takes effect with the next `factorio.service` restart.
- `scripts/pack_mod.py` builds the client-installable `<name>_<version>.zip` (top folder `<name>_<version>/`) from a mod folder, and the dashboard serves such zips at `/mods` and `/mods/<name>_<version>.zip` (strict file-name match, only regular files of `~/factorio-agent/downloads/mods`), so a human can install the same `factorio-mcp` version the server runs and join the game.
- `run_plan` accepts a `set_filters` step (x, y, filters, mode): w1 made 33 `set_filters` calls in an hour, 30 of them back to back, and 8 were refused by the 8-calls-per-turn cap. The per-turn log line also ends in `trimmed=N` (tool results cut at the 5.5k cap) and `report`'s metrics carry a `trimmed` counter.
- `tasks` tool: a persistent per-agent task list (add / doing / done / drop / list, `state/tasks/<name>.json`, 12 open tasks, 160 chars each). It is shown again at every context start (a worker's context resets about every 40 minutes and `notes_set` overwrites the whole note) and in the coach's input.
- Stalled-agent watchdog: the runner logs a WARNING when an unpaused agent has taken no LLM turn for 10 minutes (and an INFO when it recovers).
- `run_plan` accepts a `deconstruct` step (x, y: take one building down): agents wrote it in plans 27 times in a day and got the whole call rejected. The standalone `deconstruct` tool keeps the area sweep.
- Directed in-game chat (mod 0.3.13): `say(text, to="w2")` reaches one teammate's chat footer (the game chat still shows it to humans), a player addresses one agent with `@w3 ...`, and `scripts/send_chat.py` posts supervisor lines through the character-less `post_chat` RPC; other agents no longer receive lines meant for someone else. Takes effect with the next `factorio.service` restart; against an older mod `to` is ignored and the line is a broadcast.
- A running worker is told when `board.md` changes (the new board is appended to its context as a user message): workers almost never call `board_read` (w2 last did 9 h earlier), so coach boards and `directives.md` tasks only reached them after a context reset.
- KPI `produced` also counts inserters, transport belts, engine units and pipes, and the coach's trend line shows iron plate, gears, circuits, inserters and belts next to the packs, so a stall in the green-pack chain shows where it breaks (these read 0.0 before).
- `state/directives.md`: human/supervisor tasks the runner prepends to every board the coach writes (the coach sees them as input but cannot drop them).
- `production_stats` accepts `window="5m"` (mapped to 10m); tool-call arguments with trailing text keep the first JSON object instead of failing (62 failed calls in one day).
- Coach input lists the researched techs (KPI `researched`), so its research queue skips finished ones; worker prompt lists valid `run_plan` step types and the `job_wait` argument.
- Coach input has a 30-minute trend line (research, packs produced, buildings, problems) so stalls are visible; a prompt rule makes unblocking the labs the first priority.
- `LLM_EXTRA_BODY` (JSON) merged into every gateway request, e.g. `{"reasoning_effort":"low"}`; dropped automatically if the gateway rejects it. Off by default.
- opencode-runner: supervisor, per-character LLM agents, coach, quota-paced burn control, `report.py --oneline`.
- Read-only realtime status page (SSE) and history sampling; systemd user units for factorio, agents, dashboard.
- `scripts/pick_seed.py` re-rolls map seeds until spawn resources are healthy.
- Coach looks ahead to the next science pack and power capacity.
- Prompt hints: no re-scan within 3 turns, check `list_technologies` before `start_research`; research prerequisites, `can_place` before `build_plan`, drill fuel logistics, powered labs, flat `run_plan` step examples.

### Changed
- A human who joins may now play and build: `factorio-mcp-humans-spectate` defaults to off (the agents help a human clear the game; the speedrun-era "agents only" rule is gone) and the worker prompt says to never remove the human's buildings and to re-inspect when the base changed. The mod default applies on the next `factorio.service` restart; until then an admin can untick it under Mod settings > Map.
- `report.py` label `idle` renamed `since_turn` (it is the time since the last LLM turn); coach prompt slice limits are named constants in `run.py`.

### Documentation
- README: status-page screenshot, `opencode-runner/` layout row and a server-run section.

### Fixed
- Worker prompt and directives ask for at least 2 techs queued (the queue held a single tech, so the labs would idle the moment it finished).
- The coach's view of the previous board no longer starts with the 2.6k-char directives block (it filled the 2.5k slice, hiding the board text and duplicating the directives section): `board_body` cuts it out.
- Coach prompt: no invented tech names (`advanced-electronics`, `advanced-material-processing-3` do not exist), no hand-written researched-tech count, and a paused worker's priorities go to an active worker.
- `cancel_research` can remove a research head that is still under 1% (a head waiting for a pack nobody makes used to block the whole queue and could not be cancelled). Mod and tool text updated; takes effect with the next `factorio.service` restart.
- Prompts tell workers and the coach to research only techs whose science packs are produced: military-3 (needs military packs nobody makes) sat at 0% for 40+ game minutes and blocked the queue.
- Burn control rates only the samples since its last pause/resume (3 h hold after each change) and resumes below 0.8x of the remaining quota (was 0.6x over a 6 h average that kept paused agents paused: 3 active workers would have ended near 93%).
- Eliding old tool calls keeps their arguments valid JSON (long lists keep the first 2 items) instead of a `{"_elided": ...}` placeholder the model copied into new `run_plan` calls; error outputs are logged to 500 chars so the failing reason of `run_plan` shows up.
- Short tool descriptions keep the final caveat clause (`analyze_factory` "no x/y"), which stops the repeated "unknown argument(s) x, y" errors (28 so far).
- Coach reply limit raised 2500 → 4000 tokens (12 of 23 replies were cut before any board text); worker prompt asks for batched calls and no hand-counting of ASCII grids (293 worker replies were cut at max_tokens).
- `run_plan` failures now start with the failed job and its detail instead of the misleading "Plan queued" header.
- Burn control no longer pauses a worker on integer-percent noise: it needs a 3 h sample span, discounts one rounding point, and reloads samples from `history.jsonl` after a restart (w4 had been paused at 62->63%).
- A reply cut at the output limit gets a dedicated nudge (and is counted as `cut` in agent metrics) instead of the generic one.
- `analyze_factory` description says it is centred on the character and takes only `radius`.
- Truncated tool-call JSON (reply cut at `max_tokens`) is logged and the agent is told to shorten its output.
- Runner fails fast at startup when a prompt template has stray braces (`check_templates`, test in `opencode-runner/tests`).

### Changed
- Fifth worker (w5): monthly burn ~0.75-0.95%/h projects to 86-92% at the deadline; burn control pauses one if that overshoots.
- All agents run with `LLM_EXTRA_BODY={"reasoning_effort":"low"}`: ~965 vs ~376 requests/h, median completion 934 tokens, truncated replies 6.6% -> 1.7%, ~+6 techs/h vs +4, and the monthly quota burn stayed ~1%/h. Revert by deleting the line in `factorio-agents.service`.
- Fourth worker (w4) added: monthly quota burn was ~0.8%/h, leaving ~15-25% unspent at the deadline.
- opencode-runner: pacing/cadence magic numbers are named constants; `Agent` exposes `paused`/`pause`/`resume`/`summary_row` instead of the supervisor reading its internals.
- Mod and docker config target Factorio 2.1 (fluidbox, underground neighbours, array categories, `crafter_input`).
- All agents and the coach run on `opencode-go/deepseek-v4.1-flash`.
