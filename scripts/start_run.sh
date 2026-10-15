#!/usr/bin/env bash
# Create a fresh run directory (new random map, frozen mod copy, empty agent workspace) and start
# the play server. Refuses if runtime/run already exists unless --wipe is given.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/runtime/run"
if [[ -e "$RUN" ]]; then
  if [[ "${1:-}" != "--wipe" ]]; then echo "$RUN exists; pass --wipe to replace it" >&2; exit 1; fi
  docker compose -f "$ROOT/docker/compose.run.yml" down >/dev/null 2>&1 || true
  rm -rf "$RUN"
fi
mkdir -p "$RUN/factorio/config" "$RUN/factorio/mods" "$RUN/workspace"
cp "$ROOT/docker/config/server-settings.json" "$ROOT/docker/config/map-settings.json" "$RUN/factorio/config/"
# DLC_SPACE_AGE=true (passed through to compose) runs Space Age, on a map with peaceful biters:
# the Space Age win needs biter eggs, which need a captured spawner.
if [[ "${DLC_SPACE_AGE:-false}" == "true" ]]; then
  cp "$ROOT/docker/config/map-gen-settings.space-age.json" "$RUN/factorio/config/map-gen-settings.json"
else
  cp "$ROOT/docker/config/map-gen-settings.json" "$RUN/factorio/config/"
fi
cp -r "$ROOT/factorio-mcp/mod/factorio-mcp" "$RUN/factorio/mods/factorio-mcp"
docker compose -f "$ROOT/docker/compose.run.yml" up -d
for _ in $(seq 1 60); do
  docker logs llm-factorio-run 2>&1 | grep -q "to(InGame)" && break; sleep 2
done
docker logs llm-factorio-run 2>&1 | grep -E "to\(InGame\)|Error" | head -3
