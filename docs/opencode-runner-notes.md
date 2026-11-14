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
- `run.py` is ~365 lines and gaining features (trend line, burn control with a since-last-change window, coach); the `quota.py` split above is due before the next pacing change.
- 2026-11-14 audit (haiku, checked against the gateway usage export): reasoning is ~65% of quota; 80% of tool replies carry one call; 293 worker replies were cut at `max_tokens` (mostly hand-counting `scan_area` ASCII grids). Prompt now asks for batching / no hand counting; the real fix is an answer-shaped scan output (free-tile list) on the mod side. Shrink cycles (`HIGH_TOKENS`) cost ~4.7% of list cost; raising it to 60k roughly cancels out, a deeper elide target (16-20k) is the lever to try.
- Whether the gateway honours a thinking-disable flag is unverified; test on one worker before rolling out.
- `report.py` "since_turn" is seconds since the agent's last LLM turn, not game-side idleness; a real per-character idle metric needs the last job-state change from the mod.
- 2026-11-14 19:30Z audit: raw quota rate (~1.35 pt/h) is above the 1.16 pt/h needed to land on the reset, but burn control discounts one rounding point on purpose (w4 was once paused on 62->63% noise); at this pace the monthly quota ends ~2-3 h before the reset, which the goal accepts. The gateway key shows $27 of an $80 limit with ~$2.8/h recent spend; whether `limit_usd` is enforced is unverified and the runner does not watch it.
- `walk_to` errors "pathfinder found no path" (7 of w4's 31 errors in 52 min): the mod could return the nearest reachable tile; `no_fuel` problems rose 4 -> 13 in 2 h, which entities is unidentified.
- 2026-11-14 20:30Z audit: coach board goes stale between runs (finished techs still listed, `advanced-electronics` is rejected by the game, "5 boilers" vs 3 in KPI) and its pack/min figures are unlabelled (wall or game minutes). KPI `low_power` stays 0 while in-game alerts showed 30: add a satisfaction probe to `KPI_LUA`. `run_plan` errors are mostly `insert` of items the character does not hold (102 of 172 tool errors since 18:34Z): preflight inventory counts in `tools.py` / `tasks.lua`.
- PENDING DEPLOY (needs a `factorio.service` restart): `factorio-mcp/mod/.../research.lua` + `tools.py` let `cancel_research` remove a head under 1%. Deploy mod and `factorio-mcp/src` together so the tool text matches the live mod. On 2026-11-14 20:59Z military-3 was removed from the queue by hand over RCON (progress 0, nothing lost).
- `factorio-mcp/tests/mod/belts_test.lua` has 2 failing underground-belt cases ("a paired entrance names its exit", "an exit taken by a nearer entrance is named") on a clean tree: stub likely lags the 2.1 `underground_belt_neighbour` change.
- `luac` is not installed on mini; Lua syntax is only checked by loading the files in the lupa tests.
