# Run 4 record (Space Age, paused at tick ~8.40M)

Copies of the run's working files, taken when the run stopped. The live originals are in the gitignored
`runtime/run/`. Lessons are in [`../lessons-run4.md`](../lessons-run4.md).

| File | What |
|---|---|
| `PLAYBOOK.md` | the worker playbook every worker read at the start of a stint |
| `board.md` | the planner's task board: assignments, worker progress reports, rules learned during the run, and the final "RUN PAUSED" state |
| `agents.tsv` | the agent ledger: every stint with model, effort, start time and character (end times are incomplete) |
| `run-result.json` | written by the mod: all 145 rocket launches with tick, silo, rider and cargo |

The workers' layout scripts (`runtime/run/workspace/layouts/`) are left out on purpose. A future run may not
start with pre-written layout generators in the environment.

To resume the run: start `llm-factorio-run` again with `DLC_SPACE_AGE=true`. The save is
`runtime/run/factorio/saves/llm-run.zip`. The first jobs are listed at the end of `board.md`.
