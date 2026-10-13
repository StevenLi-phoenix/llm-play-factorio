"""Offline tests for the harness RPCs (mod 0.2.23): register_blueprint,
list_registered_blueprints and area_snapshot. They are unscoped (no character,
no session) and are deliberately not MCP tools; the Python side is the bridge
and game helpers plus the `snapshot` / `register-blueprint` CLI commands."""

from __future__ import annotations

import json
import re

import pytest

from factorio_mcp import cli
from factorio_mcp import tools as T
from factorio_mcp.bridge import UNSCOPED, Bridge, ModError, normalize_snapshot
from factorio_mcp.game import Config, Game

HARNESS = ("register_blueprint", "list_registered_blueprints", "area_snapshot")


class FakeRcon:
    def __init__(self, *replies):
        self.replies = list(replies)
        self.commands = []

    async def exec(self, cmd):
        self.commands.append(cmd)
        if not self.replies:
            raise AssertionError("unexpected RCON command: " + cmd)
        return self.replies.pop(0)

    def close(self):
        pass


def env(data=None, error=None):
    return json.dumps({"ok": False, "error": error} if error else {"ok": True, "data": data if data is not None else {}})


def sent_params(cmd: str) -> dict:
    m = re.search(r'"rpc","\w+","(.*)"\)$', cmd)
    return json.loads(m.group(1).replace('\\"', '"').replace("\\\\", "\\"))


def test_harness_rpcs_are_unscoped_and_not_tools():
    assert set(HARNESS) <= UNSCOPED
    src = open(T.__file__, encoding="utf-8").read()
    for name in HARNESS:
        assert f'"{name}"' not in src, f"{name} must not be called from tools.py"


async def test_register_blueprint_sends_no_character_or_session():
    rcon = FakeRcon(env({"key_hash": "ab" * 16, "entity_count": 3, "already_registered": False}))
    b = Bridge(rcon, "scout-1", "session-1234")
    r = await b.register_blueprint("0eNq", "compiled", note="from layout.json")
    assert r["key_hash"] == "ab" * 16 and r["entity_count"] == 3
    p = sent_params(rcon.commands[0])
    assert p == {"string": "0eNq", "source": "compiled", "note": "from layout.json"}
    assert '"register_blueprint"' in rcon.commands[0]


async def test_register_blueprint_omits_empty_note():
    rcon = FakeRcon(env({"key_hash": "x", "entity_count": 1}))
    await Bridge(rcon, "c").register_blueprint("0eNq", "export")
    assert "note" not in sent_params(rcon.commands[0])


async def test_register_blueprint_error_surfaces():
    b = Bridge(FakeRcon(env(error="that blueprint is empty — nothing to register")), "c")
    with pytest.raises(ModError, match="empty"):
        await b.register_blueprint("0eNq", "compiled")


async def test_list_registered_blueprints_normalizes_empty():
    b = Bridge(FakeRcon(env({"enforced": True, "total": 0, "blueprints": {}})), "c")
    r = await b.list_registered_blueprints()
    assert r == {"enforced": True, "total": 0, "blueprints": []}


async def test_area_snapshot_params_and_empty_lists_become_lists():
    # Factorio serializes empty tables as {}: the shape must not depend on how sparse the area is
    reply = {"tick": 5, "area": [-40, -40, 40, 40], "unexplored_chunks": {}, "entities": {}, "resources": {},
             "water": {}, "obstacles": {}}
    rcon = FakeRcon(env(reply))
    snap = await Bridge(rcon, "c").area_snapshot(-40, -40, 40, 40)
    assert sent_params(rcon.commands[0]) == {"x1": -40, "y1": -40, "x2": 40, "y2": 40}
    assert snap == {"tick": 5, "area": [-40, -40, 40, 40], "unexplored_chunks": [], "entities": [],
                    "resources": {}, "water": [], "obstacles": []}


def test_normalize_snapshot_rounds_float_dust():
    # the game's Lua parses "-0.91" one ulp off: -0.9099999999999999
    snap = normalize_snapshot({"obstacles": [[-0.9099999999999999, 84.34, 0.29, 85.54000000000001, "tree"]],
                               "entities": [{"x": 3.0000000000000004, "y": 3, "dir": 4}], "tick": 7})
    assert snap["obstacles"] == [[-0.91, 84.34, 0.29, 85.54, "tree"]]
    assert snap["entities"] == [{"x": 3.0, "y": 3, "dir": 4}] and snap["tick"] == 7
    assert repr(snap["obstacles"][0][0]) == "-0.91"


def test_normalize_snapshot_keeps_data():
    snap = normalize_snapshot({
        "tick": 1, "area": [0, 0, 1, 1], "unexplored_chunks": [[0, 0]],
        "entities": [{"name": "stone-furnace"}], "resources": {"iron-ore": [[1, 2, 300]], "coal": {}},
        "water": [[3, 4]], "obstacles": [[0, 0, 1, 1, "tree"]],
    })
    assert snap["entities"] == [{"name": "stone-furnace"}]
    assert snap["resources"] == {"iron-ore": [[1, 2, 300]], "coal": []}
    assert snap["water"] == [[3, 4]] and snap["unexplored_chunks"] == [[0, 0]]


async def test_area_snapshot_reassembles_chunked_replies():
    big = {"tick": 1, "area": [0, 0, 9, 9], "unexplored_chunks": [], "entities": [{"name": "x" * 3000}],
           "resources": {}, "water": [], "obstacles": []}
    full = env(big)
    parts = [full[i:i + 1000] for i in range(0, len(full), 1000)]
    first = json.dumps({"ok": True, "chunked": True, "id": 3, "parts": len(parts), "data": parts[0]})
    rest = [env({"data": p}) for p in parts[1:]]
    rcon = FakeRcon(first, *rest)
    snap = await Bridge(rcon, "c").area_snapshot(0, 0, 9, 9)
    assert snap["entities"][0]["name"] == "x" * 3000


async def test_game_helpers_bind_no_character():
    rcon = FakeRcon(
        env({"protocol_version": 6, "mod_version": "0.2.23"}),  # the unlock ping
        env({"tick": 1, "area": [0, 0, 5, 5], "unexplored_chunks": {}, "entities": {}, "resources": {},
             "water": {}, "obstacles": {}}),
        env({"enforced": False, "total": 0, "blueprints": {}}),
    )
    g = Game(Config(character="nobody"))
    g._rcon = rcon
    g._bridge = Bridge(rcon, "nobody")
    snap = await g.area_snapshot(0, 0, 5, 5)
    assert snap["entities"] == []
    assert (await g.list_registered_blueprints())["enforced"] is False
    methods = [re.search(r'"rpc","(\w+)"', c).group(1) for c in rcon.commands]
    assert methods == ["ping", "area_snapshot", "list_registered_blueprints"]  # no bind


def test_cli_snapshot_prints_json(monkeypatch, capsys):
    seen = {}

    async def fake_snapshot(self, x1, y1, x2, y2):
        seen["area"] = (x1, y1, x2, y2)
        return {"tick": 9, "area": [x1, y1, x2, y2], "entities": []}

    async def fake_close(self):
        pass

    monkeypatch.setattr(Game, "area_snapshot", fake_snapshot)
    monkeypatch.setattr(Game, "close", fake_close)
    with pytest.raises(SystemExit) as e:
        cli.main(["--password", "pw", "snapshot", "-40", "-40", "40", "40"])
    assert e.value.code == 0
    assert seen["area"] == (-40.0, -40.0, 40.0, 40.0)
    assert json.loads(capsys.readouterr().out)["tick"] == 9


def test_cli_snapshot_needs_four_numbers(capsys):
    with pytest.raises(SystemExit) as e:
        cli.main(["--password", "pw", "snapshot", "1", "2", "3"])
    assert e.value.code == 2


def test_cli_register_blueprint_reads_a_file(monkeypatch, capsys, tmp_path):
    seen = {}

    async def fake_register(self, string, source, note=None):
        seen.update(string=string, source=source, note=note)
        return {"key_hash": "k", "entity_count": 2, "already_registered": False}

    async def fake_close(self):
        pass

    monkeypatch.setattr(Game, "register_blueprint", fake_register)
    monkeypatch.setattr(Game, "close", fake_close)
    f = tmp_path / "bp.txt"
    f.write_text("0eNqabc\n", encoding="utf-8")
    with pytest.raises(SystemExit) as e:
        cli.main(["--password", "pw", "register-blueprint", f"@{f}", "--source", "compiled", "--note", "n"])
    assert e.value.code == 0
    assert seen == {"string": "0eNqabc", "source": "compiled", "note": "n"}
    assert json.loads(capsys.readouterr().out)["key_hash"] == "k"


def test_cli_register_blueprint_requires_source():
    with pytest.raises(SystemExit) as e:
        cli.main(["--password", "pw", "register-blueprint", "0eNq"])
    assert e.value.code == 2
