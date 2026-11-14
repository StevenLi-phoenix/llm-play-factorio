"""Call every read-only tool once against the live server and print only failures (Factorio API drift check).
  RUNNER env as runner.sh: FACTORIO_RCON_PORT/PASSWORD. Usage: python smoke_tools.py [character]"""
import asyncio
import os
import sys

from factorio_mcp.game import Config
from factorio_mcp.server import build_app

CALLS = [
    ("status", {}), ("look_around", {"radius": 60}), ("check_inventory", {}), ("map_overview", {}),
    ("scan_area", {"radius": 20}), ("scan_area", {"radius": 100}), ("inspect_entity", {"x": 0, "y": 0}),
    ("describe_prototype", {"names": ["burner-mining-drill", "lab", "assembling-machine-2", "oil-refinery", "chemical-plant",
                                      "pumpjack", "offshore-pump", "steam-engine", "boiler", "pipe-to-ground", "underground-belt",
                                      "rocket-silo", "foundry", "biochamber", "recycler", "space-platform-hub", "iron-plate", "coal", "wood"]}),
    ("describe_prototype", {"names": ["fluid-wagon", "storage-tank", "pump", "fusion-reactor", "heat-pipe", "car", "tank", "cargo-landing-pad"]}),
    ("map_warnings", {}), ("analyze_factory", {}), ("list_technologies", {}), ("list_technologies", {"filter": "all"}),
    ("list_blueprints", {}), ("platforms", {}), ("get_events", {}), ("read_chat", {}), ("job_status", {}),
    ("trace_belt", {"x": 0, "y": 0}), ("measure_belt", {"x": 0, "y": 0}), ("map_warnings", {}),
]


async def main():
    char = sys.argv[1] if len(sys.argv) > 1 else "smoke"
    app = build_app(Config(port=int(os.environ.get("FACTORIO_RCON_PORT", "27017")), password=os.environ["FACTORIO_RCON_PASSWORD"],
                           character=char, takeover=True))
    bad = 0
    for name, args in CALLS:
        try:
            r = await asyncio.wait_for(app.call_tool(name, args), 60)
            text = "\n".join(c.text for c in r.content if getattr(c, "text", None))
            err = getattr(r, "is_error", False)
        except Exception as e:  # noqa: BLE001
            text, err = f"{type(e).__name__}: {e}", True
        if err or "attempt to" in text or "doesn't contain key" in text or "stack traceback" in text:
            bad += 1
            print(f"FAIL {name} {args if len(str(args)) < 90 else '...'}: {text[:260]}")
        else:
            print(f"ok   {name} ({len(text)} chars)")
    await app._game.close()
    print("failures:", bad)


asyncio.run(main())
