"""Directed chat (mod 0.3.13): say(to=...), the `->` in chat lines and the character-less post_chat RPC."""

from __future__ import annotations

from factorio_mcp.bridge import Bridge

from test_research_tools import FakeRcon, env, registered


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
