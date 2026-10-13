#!/usr/bin/env bash
# Prepare a fresh run: wipe the previous run's saves/script-output and re-copy config templates.
# Usage: scripts/new_run.sh [--seed N] [--yes]
# The container must be stopped. Without --yes it only prints what it would delete.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RT="$ROOT/runtime/factorio"
SEED=""
YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed) SEED="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

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
echo "ready: docker compose -f docker/compose.yml up -d"
