"""ghost_build / ghost_clear (mod 0.3.14): blueprint ghosts on the character's surface."""

from __future__ import annotations

from factorio_mcp import tools as T
from factorio_mcp.bridge import Bridge
from factorio_mcp.tools import GhostStep

from test_research_tools import FakeRcon, env, registered


async def test_ghost_build_reports_placed_and_rejected():
    data = {"surface": "nauvis", "placed": 2, "placed_by_name": {"electric-mining-drill": 1, "transport-belt": 1},
            "rejected": [{"i": 3, "name": "stone-furnace", "x": 9.5, "y": 2.0, "why": "blocked (overlaps a building)"}],
            "rejected_total": 1}
    rcon = FakeRcon(env(data=data))
    steps = [GhostStep(name="electric-mining-drill", x=1.5, y=1.5, direction=4),
             GhostStep(name="transport-belt", x=3.5, y=0.5),
             GhostStep(name="stone-furnace", x=9.5, y=2)]
    out = await registered(Bridge(rcon, "w1"), inbox=False).registry["ghost_build"](steps)
    assert "2 ghost(s) placed on nauvis" in out and "1 electric-mining-drill" in out and "1 transport-belt" in out
    assert "1 rejected" in out and "step 3 stone-furnace at (9.5, 2.0): blocked" in out
    assert "ghost_build" in rcon.commands[0]
    assert "nothing was built" in out


async def test_ghost_clear_reports_removed():
    rcon = FakeRcon(env(data={"removed": 7}))
    out = await registered(Bridge(rcon, "w1"), inbox=False).registry["ghost_clear"](0, 0, 20, 20)
    assert out == "7 ghost(s) deleted in (0, 0)-(20, 20)."


def test_ghost_tools_are_gated_on_the_mod_version():
    assert T.gated_tools(["ghost_build", "ghost_clear", "status"], (0, 3, 13)) == ["ghost_build", "ghost_clear"]
    assert T.gated_tools(["ghost_build", "ghost_clear"], (0, 3, 14)) == []


async def test_count_dx_dy_repeat_a_step_before_it_goes_to_the_game():
    rcon = FakeRcon(env(data={"surface": "nauvis", "placed": 3, "placed_by_name": {"electric-mining-drill": 3}, "rejected": [], "rejected_total": 0}))
    steps = [GhostStep(name="electric-mining-drill", x=1.5, y=1.5, direction=8, count=3, dx=3)]
    await registered(Bridge(rcon, "w1"), inbox=False).registry["ghost_build"](steps)
    cmd = rcon.commands[0].replace("\\", "")
    assert cmd.count('"name":"electric-mining-drill"') == 3
    assert '"x":4.5' in cmd and '"x":7.5' in cmd and "count" not in cmd


def test_expand_ghost_steps_keeps_direction_and_recipe():
    from factorio_mcp.tools import expand_ghost_steps
    out = expand_ghost_steps([GhostStep(name="inserter", x=0.5, y=0.5, direction=8, count=2, dy=2)])
    assert out == [{"name": "inserter", "x": 0.5, "y": 0.5, "direction": 8}, {"name": "inserter", "x": 0.5, "y": 2.5, "direction": 8}]
