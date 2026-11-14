#!/usr/bin/env bash
# Start the supervisor in the foreground with the server's env (key/RCON from 600 files, never echoed).
set -euo pipefail
H=$HOME/factorio-agent
set -a; . $H/.env; set +a
export FACTORIO_RCON_PASSWORD="$(cat $H/run/config/rconpw)" FACTORIO_RCON_PORT=27017
export RUNNER_ROOT=${RUNNER_ROOT:-$H/state}
cd $H/repo/opencode-runner
export PATH=$HOME/.local/bin:$PATH
exec uv run --project $H/repo/opencode-runner python run.py
