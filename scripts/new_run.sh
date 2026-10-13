#!/usr/bin/env bash
# Prepare a fresh run: wipe the previous run's saves/script-output and re-copy config templates.
# Usage: scripts/new_run.sh [--seed N] [--save FILE | --no-replay] [--yes]
# The container must be stopped. Without --yes it only prints what it would delete.
#
# Every official run needs replay recording, which only a full client can switch on when the
# map is created (headless --create has no option for it). Flow:
#   1. scripts/new_run.sh --no-replay --yes && docker compose -f docker/compose.yml up -d
#   2. python -I scripts/map_exchange.py        -> map exchange string with this run's seed
#   3. full client (2.0.77, same mods, Space Age mods off): New game, tick "Record replay",
#      import the string, Play, save, quit
#   4. docker compose -f docker/compose.yml down && scripts/new_run.sh --save <save.zip> --yes
#   5. docker compose -f docker/compose.yml up -d
# --no-replay alone is for dev/test servers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RT="$ROOT/runtime/factorio"
SEED=""
SAVE=""
NO_REPLAY=0
YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed) SEED="$2"; shift 2 ;;
    --save) SAVE="$2"; shift 2 ;;
    --no-replay) NO_REPLAY=1; shift ;;
    --yes) YES=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$SAVE" && $NO_REPLAY -ne 1 ]]; then
  echo "give --save FILE (a replay-enabled save from a full client) or --no-replay for a dev map" >&2
  exit 2
fi
if [[ -n "$SAVE" ]]; then
  # A replay-enabled save carries its recording as <name>/replay.dat inside the zip.
  python -I -c 'import sys,zipfile; n=zipfile.ZipFile(sys.argv[1]).namelist(); sys.exit(0 if any(x.endswith("/replay.dat") for x in n) else 1)' "$SAVE"     || { echo "$SAVE has no replay data; create it with \"Record replay\" ticked" >&2; exit 1; }
fi

if docker ps --format '{{.Names}}' | grep -qx llm-factorio; then
  echo "llm-factorio is running; stop it first: docker compose -f docker/compose.yml down" >&2
  exit 1
fi

TARGETS=("$RT/saves" "$RT/script-output")
echo "will delete:"; for t in "${TARGETS[@]}"; do [[ -e "$t" ]] && echo "  $t"; done
if [[ $YES -ne 1 ]]; then echo "(dry run; pass --yes to proceed)"; exit 0; fi

for t in "${TARGETS[@]}"; do rm -rf "$t"; done
mkdir -p "$RT/config" "$RT/mods" "$RT/saves"
cp "$ROOT/docker/config/server-settings.json" "$RT/config/"
cp "$ROOT/docker/config/map-settings.json" "$RT/config/"
if [[ -n "$SEED" ]]; then
  python -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(sys.argv[2])); d["seed"]=int(sys.argv[3]); json.dump(d,open(p,"w"),indent=2)' \
    "$RT/config/map-gen-settings.json" "$ROOT/docker/config/map-gen-settings.json" "$SEED"
else
  cp "$ROOT/docker/config/map-gen-settings.json" "$RT/config/"
fi
if [[ -n "$SAVE" ]]; then
  cp "$SAVE" "$RT/saves/llm-run.zip"   # compose loads SAVE_NAME=llm-run; generation is skipped when it exists
  echo "installed $SAVE as saves/llm-run.zip (replay data present)"
fi
echo "ready: docker compose -f docker/compose.yml up -d"
