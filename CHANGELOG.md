# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased] - 2026-11-14

### Added
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
- `report.py` label `idle` renamed `since_turn` (it is the time since the last LLM turn); coach prompt slice limits are named constants in `run.py`.

### Documentation
- README: status-page screenshot, `opencode-runner/` layout row and a server-run section.

### Fixed
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
