# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased] - 2026-11-14

### Added
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
