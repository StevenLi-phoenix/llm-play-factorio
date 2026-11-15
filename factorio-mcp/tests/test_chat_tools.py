"""Directed chat (mod 0.3.13): say(to=...), the `->` in chat lines and the character-less post_chat RPC."""

from __future__ import annotations

from factorio_mcp.bridge import Bridge
from factorio_mcp.tools import PlanStep

from factorio_mcp import tools as T

from test_research_tools import FakeApp, FakeGame, FakeRcon, env, registered


async def test_say_with_to_sends_the_recipient():
    rcon = FakeRcon(env(data={}))
    out = await registered(Bridge(rcon, "w1"), inbox=False).registry["say"]("gears ready", to="w4")
    assert out == "Said to w4."
    assert r'\"to\":\"w4\"' in rcon.commands[0] and r'\"text\":\"gears ready\"' in rcon.commands[0]


async def test_say_without_to_is_a_broadcast():
    rcon = FakeRcon(env(data={}))
    out = await registered(Bridge(rcon, "w1"), inbox=False).registry["say"]("hello")
    assert out == "Said." and '"to"' not in rcon.commands[0].replace(r'\"', '"')


async def test_read_chat_shows_who_a_line_is_for():
    msgs = [{"id": 7, "player": "stevenli", "text": "@w1 fuel the boilers", "to": "w1"},
            {"id": 8, "player": "w2", "bot": True, "text": "done", "to": "w1"},
            {"id": 9, "player": "w3", "bot": True, "text": "hi all"}]
    rcon = FakeRcon(env(data={"messages": msgs, "last_id": 9}))
    out = await registered(Bridge(rcon, "w1"), inbox=False).registry["read_chat"]()
    assert "[chat #7] <stevenli -> w1> @w1 fuel the boilers" in out
    assert "[chat #8] <w2 (agent) -> w1> done" in out
    assert "[chat #9] <w3 (agent)> hi all" in out


async def test_post_chat_needs_no_character():
    rcon = FakeRcon(env(data={}))
    b = Bridge(rcon, "w1", "session-1234")
    await b.call("post_chat", {"from": "supervisor", "to": "w2", "text": "restart in 5 min"})
    assert "companion" not in rcon.commands[0] and "session" not in rcon.commands[0]


def test_send_chat_script_builds_the_same_command_as_the_bridge():
    import json
    import sys
    from pathlib import Path

    from factorio_mcp.bridge import escape_lua_string

    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
    import send_chat

    cmd = send_chat.build_command('say "hi"', "w3")
    body = {"text": 'say "hi"', "from": "supervisor", "to": "w3"}
    expected = escape_lua_string(json.dumps(body, separators=(",", ":")))
    assert cmd == f'/silent-command remote.call("factorio_mcp","rpc","post_chat","{expected}")'
    assert '"to"' not in send_chat.build_command("x").replace('\\"', '"')


async def test_run_plan_accepts_a_deconstruct_step():
    """Agents kept writing {"type": "deconstruct"} in run_plan (27 rejected calls in a day): taking a building down can be chained."""
    rcon = FakeRcon(env(data={"task_id": 5}))
    game = FakeGame(Bridge(rcon, "w1"), inbox=False)
    game.queue = None  # the job-queue chain key the real Game exposes
    app = FakeApp()
    T.register(app, game)
    out = await app.registry["run_plan"](
        steps=[PlanStep(type="deconstruct", x=12.5, y=30.5)], wait_s=0)
    assert out == "Plan queued: #5 deconstruct."
    cmd = rcon.commands[0].replace('\\"', '"')
    assert '"type":"deconstruct"' in cmd and '"target":{"x":12.5,"y":30.5}' in cmd


async def test_run_plan_accepts_set_filters_steps():
    """w1 made 33 set_filters calls in an hour, 30 back to back, and hit the 8-calls-per-turn cap: filters can be chained."""
    rcon = FakeRcon(env(data={"task_id": 6}), env(data={"task_id": 7}))
    game = FakeGame(Bridge(rcon, "w1"), inbox=False)
    game.queue = None
    app = FakeApp()
    T.register(app, game)
    out = await app.registry["run_plan"](
        steps=[PlanStep(type="set_filters", x=1.5, y=2.5, filters=["iron-plate"]),
               PlanStep(type="set_filters", x=3.5, y=2.5, filters=[], mode="blacklist")], wait_s=0)
    assert out == "Plan queued: #6 set_filters, #7 set_filters."
    first = rcon.commands[0].replace('\\"', '"')
    assert '"type":"set_filters"' in first and '"filters":["iron-plate"]' in first and '"target":{"x":1.5,"y":2.5}' in first
    assert '"mode":"blacklist"' in rcon.commands[1].replace('\\"', '"')
