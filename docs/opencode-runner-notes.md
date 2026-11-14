# opencode-runner: open design notes

Things reviewed and left for later (each is bigger than a safe small commit).

- `run.py` mixes quota pacing, KPI sampling, the coach and reporting in one `Supervisor` (~300 lines). Split `quota.py` (quota_loop + control_burn) out once a second pacing policy is needed.
- `agent.py` writes `status/<name>.json` metrics and reads `board.md`/`notes/` by path; `run.py` and `dashboard.py` read the same files by path. The file layout under `RUNNER_ROOT` is the shared contract; keep it in one `paths` module if more readers appear.
- No stuck-loop detection: an agent repeating the same failing call keeps spending tokens. Add repeat-call detection in `Agent._call` (same tool+args N times -> nudge, then summarize).
- Reasoning dominates latency on hard turns (4k+ reasoning tokens, 40-50 s). Try a lower `max_tokens` / reasoning effort on routine turns and A/B on one worker.
- Game speed is fixed (`GAME_SPEED`); tune it against measured UPS instead.
- Tool errors for crafting should report need/have counts (factorio-mcp side), so agents stop retrying blind.
- `dashboard.py` re-reads whole jsonl files when they change; fine for a day of data, switch to tail/offset reads if history passes ~10 MB.
