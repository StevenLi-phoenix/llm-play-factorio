#!/usr/bin/env bash
# Dump base-game (no DLC) data.raw to data/game/data-raw-dump.json for the renderer/simulator.
# Game data is not redistributable, so data/game/ is gitignored.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/data/game"
mkdir -p "$OUT"
MOUNT="$OUT"
command -v cygpath >/dev/null && MOUNT="$(cygpath -w "$OUT")"
MSYS_NO_PATHCONV=1 docker run --rm --entrypoint sh -v "$MOUNT:/out" factoriotools/factorio:2.0.77 -c '
mkdir -p /tmp/mods
echo "{\"mods\":[{\"name\":\"base\",\"enabled\":true},{\"name\":\"space-age\",\"enabled\":false},{\"name\":\"quality\",\"enabled\":false},{\"name\":\"elevated-rails\",\"enabled\":false}]}" > /tmp/mods/mod-list.json
/opt/factorio/bin/x64/factorio --mod-directory /tmp/mods --dump-data >/dev/null
cp /opt/factorio/script-output/data-raw-dump.json /out/'
ls -la "$OUT/data-raw-dump.json"
