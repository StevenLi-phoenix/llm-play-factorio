# opencode-runner: open design notes

Things reviewed and left for later (each is bigger than a safe small commit).

- `run.py` mixes quota pacing, KPI sampling, the coach and reporting in one `Supervisor` (~300 lines). Split `quota.py` (quota_loop + control_burn) out once a second pacing policy is needed.
- `agent.py` writes `status/<name>.json` metrics and reads `board.md`/`notes/` by path; `run.py` and `dashboard.py` read the same files by path. The file layout under `RUNNER_ROOT` is the shared contract; keep it in one `paths` module if more readers appear.
- No stuck-loop detection: an agent repeating the same failing call keeps spending tokens. Add repeat-call detection in `Agent._call` (same tool+args N times -> nudge, then summarize).
- Reasoning dominates latency on hard turns (4k+ reasoning tokens, 40-50 s). Try a lower `max_tokens` / reasoning effort on routine turns and A/B on one worker.
- Game speed is fixed (`GAME_SPEED`); tune it against measured UPS instead.
- Tool errors for crafting should report need/have counts (factorio-mcp side), so agents stop retrying blind.
- `dashboard.py` re-reads whole jsonl files when they change; fine for a day of data, switch to tail/offset reads if history passes ~10 MB.
- `quota_start_pct` ("burned N pts since start" on the status page) resets on every runner restart; persist the first value in `RUNNER_ROOT` so the burn figure spans the whole run.
- `opencode-runner/uv.lock` is committed (reproducible installs); regenerate it with `uv lock` after changing dependencies, and check the server still starts after a re-sync.
- `run.py` is ~340 lines and gaining features (trend line, burn control, coach); the `quota.py` split above is now due before the next pacing feature.
- 2026-11-14 audit (haiku, checked against the gateway usage export): reasoning is ~65% of quota; 80% of tool replies carry one call; 293 worker replies were cut at `max_tokens` (mostly hand-counting `scan_area` ASCII grids). Prompt now asks for batching / no hand counting; the real fix is an answer-shaped scan output (free-tile list) on the mod side. Shrink cycles (`HIGH_TOKENS`) cost ~4.7% of list cost; raising it to 60k roughly cancels out, a deeper elide target (16-20k) is the lever to try.
- Whether the gateway honours a thinking-disable flag is unverified; test on one worker before rolling out.
- `report.py` "since_turn" is seconds since the agent's last LLM turn, not game-side idleness; a real per-character idle metric needs the last job-state change from the mod.
