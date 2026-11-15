"""Live agent output: stream.StreamWriter appends events, dashboard.read_backlog / StreamTail push them."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import dashboard  # noqa: E402
import stream  # noqa: E402


def test_writer_appends_one_json_line_per_event(tmp_path):
    w = stream.StreamWriter(tmp_path, "w1")
    w.emit("think", "hmm", turn=3)
    w.emit("call", "scan_area({})", turn=3)
    rows = [json.loads(l) for l in (tmp_path / "stream" / "w1.jsonl").read_text().splitlines()]
    assert [r["kind"] for r in rows] == ["think", "call"]
    assert rows[0]["agent"] == "w1" and rows[0]["turn"] == 3 and rows[0]["text"] == "hmm" and rows[0]["ts"] > 0


def test_writer_caps_long_text_and_says_so(tmp_path):
    w = stream.StreamWriter(tmp_path, "w1")
    w.emit("result", "x" * 50_000, turn=1)
    row = json.loads((tmp_path / "stream" / "w1.jsonl").read_text())
    assert len(row["text"]) < 50_000 and "chars cut" in row["text"]


def test_writer_ignores_empty_text(tmp_path):
    stream.StreamWriter(tmp_path, "w1").emit("say", "   ", turn=1)
    assert not (tmp_path / "stream" / "w1.jsonl").exists()


def test_backlog_is_the_last_n_events_in_time_order(tmp_path):
    a, b = stream.StreamWriter(tmp_path, "w1"), stream.StreamWriter(tmp_path, "w2")
    for i in range(5):
        a.emit("say", f"a{i}", turn=i)
        b.emit("say", f"b{i}", turn=i)
    rows = dashboard.read_backlog(tmp_path, 4)
    assert len(rows) == 4 and [r["ts"] for r in rows] == sorted(r["ts"] for r in rows)
    assert {r["agent"] for r in dashboard.read_backlog(tmp_path, 50, agent="w2")} == {"w2"}


def test_tail_returns_only_new_complete_lines(tmp_path):
    w = stream.StreamWriter(tmp_path, "w1")
    w.emit("say", "old", turn=1)
    tail = dashboard.StreamTail(tmp_path)
    assert tail.poll() == []
    w.emit("say", "new", turn=2)
    assert [r["text"] for r in tail.poll()] == ["new"]
    with (tmp_path / "stream" / "w1.jsonl").open("a") as fh:
        fh.write('{"ts": 1, "agent": "w1", "kind": "say", "tex')   # a half-written line
    assert tail.poll() == []
    with (tmp_path / "stream" / "w1.jsonl").open("a") as fh:
        fh.write('t": "done", "turn": 3}\n')
    assert [r["text"] for r in tail.poll()] == ["done"]


def test_tail_picks_up_an_agent_that_starts_later(tmp_path):
    tail = dashboard.StreamTail(tmp_path)
    stream.StreamWriter(tmp_path, "w3").emit("say", "hello", turn=1)
    assert [r["agent"] for r in tail.poll()] == ["w3"]


def test_agent_filter_is_a_strict_name():
    assert dashboard.valid_agent("w1") and dashboard.valid_agent(None)
    assert not dashboard.valid_agent("../etc/passwd") and not dashboard.valid_agent("w1/../../x")
