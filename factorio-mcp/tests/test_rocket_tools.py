"""Offline tests for the 0.2.24 rocket tools: the launch_rocket job tool and
the silo text in status / inspect_entity, plus the client-side gating that
holds launch_rocket back against older mods."""

from __future__ import annotations

import json
import re

from factorio_mcp import format as fmt
from factorio_mcp import tools as T
from factorio_mcp.bridge import Bridge
from test_research_tools import FakeApp, FakeGame, FakeRcon, env


class QueueGame(FakeGame):
    queue = "test-1:abc"


async def test_launch_rocket_enqueues_a_job_at_the_silo():
    rcon = FakeRcon(env({"task_id": 7}))
    app, game = FakeApp(), QueueGame(Bridge(rcon, "test-1"), inbox=False)
    T.register(app, game)
    out = await app.registry["launch_rocket"](x=60.5, y=-60.5, wait_s=0)
    assert out == "Job #7 (launch_rocket) queued."
    m = re.search(r'"rpc","enqueue","(.*)"\)$', rcon.commands[0])
    sent = json.loads(m.group(1).replace('\\"', '"').replace("\\\\", "\\"))
    assert sent["task"] == {"type": "launch_rocket", "target": {"x": 60.5, "y": -60.5}}
    assert sent["chain"] == "test-1:abc"


def test_launch_rocket_is_gated_on_the_mod_version():
    assert "launch_rocket" in T.TOOL_MIN_MOD
    assert T.gated_tools(["launch_rocket", "status"], (0, 2, 23)) == ["launch_rocket"]
    assert T.gated_tools(["launch_rocket", "status"], (0, 2, 24)) == []


def test_silo_text_covers_every_stage():
    base = {"parts_required": 100, "cargo": {}}
    assert fmt.silo_text({**base, "parts": 37, "has_rocket": False}) == "no rocket yet, 37/100 rocket parts"
    assert fmt.silo_text({**base, "parts": 0, "has_rocket": True, "phase": "doors_opening", "status": "no_power"}) == (
        "a rocket is being prepared (doors opening); cargo: empty; silo status: no power")
    assert fmt.silo_text({**base, "parts": 0, "has_rocket": True, "ready": True, "phase": "rocket_ready",
                          "cargo": {"raw-fish": 3}, "status": "working"}) == (
        "a rocket is READY to launch; cargo: raw-fish x3")
    assert fmt.silo_text({**base, "parts": 0, "has_rocket": False, "launching": True, "phase": "doors_closing"}).startswith(
        "launching (doors closing)")


def test_state_lists_silos_and_the_launch_result():
    text = fmt.state({
        "rocket_silos": [{"x": 60.5, "y": -60.5, "parts": 100, "parts_required": 100, "has_rocket": False}],
        "rocket_launched": {"tick": 9216, "character": "test-1", "payload": {"raw-fish": 3}},
    })
    assert "Rocket silo at (60.50, -60.50): no rocket yet, 100/100 rocket parts." in text
    assert "ROCKET LAUNCHED at tick 9216 by test-1, payload: raw-fish x3." in text


def test_inspect_shows_the_rocket():
    text = fmt.inspect({"name": "rocket-silo", "type": "rocket-silo", "position": {"x": 60.5, "y": -60.5},
                        "rocket": {"parts": 37, "parts_required": 100, "has_rocket": False, "cargo": {}}})
    assert "Rocket: no rocket yet, 37/100 rocket parts." in text
