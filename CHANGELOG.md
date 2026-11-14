# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased] - 2026-11-14

### Added
- `LLM_EXTRA_BODY` (JSON) merged into every gateway request, e.g. `{"reasoning_effort":"low"}`; dropped automatically if the gateway rejects it. Off by default.
- opencode-runner: supervisor, per-character LLM agents, coach, quota-paced burn control, `report.py --oneline`.
- Read-only realtime status page (SSE) and history sampling; systemd user units for factorio, agents, dashboard.
- `scripts/pick_seed.py` re-rolls map seeds until spawn resources are healthy.
- Coach looks ahead to the next science pack and power capacity.
- Prompt hints: research prerequisites, `can_place` before `build_plan`, drill fuel logistics, powered labs, flat `run_plan` step examples.

### Documentation
- README: status-page screenshot, `opencode-runner/` layout row and a server-run section.

### Fixed
- Truncated tool-call JSON (reply cut at `max_tokens`) is logged and the agent is told to shorten its output.
- Runner fails fast at startup when a prompt template has stray braces (`check_templates`, test in `opencode-runner/tests`).

### Changed
- Fourth worker (w4) added: monthly quota burn was ~0.8%/h, leaving ~15-25% unspent at the deadline.
- opencode-runner: pacing/cadence magic numbers are named constants; `Agent` exposes `paused`/`pause`/`resume`/`summary_row` instead of the supervisor reading its internals.
- Mod and docker config target Factorio 2.1 (fluidbox, underground neighbours, array categories, `crafter_input`).
- All agents and the coach run on `opencode-go/deepseek-v4.1-flash`.
