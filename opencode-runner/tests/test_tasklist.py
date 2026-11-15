"""tasklist: a persistent per-agent task list that survives context resets (notes_set overwrites everything)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import tasklist  # noqa: E402


def _apply(path, op, text=None, task_id=None):
    return tasklist.apply(path, op, text, task_id)


def test_add_assigns_increasing_ids_and_persists(tmp_path):
    p = tmp_path / "w1.json"
    assert "T1" in _apply(p, "add", "feed boilers")
    out = _apply(p, "add", "rebuild west iron")
    assert "T1" in out and "T2" in out and "rebuild west iron" in out
    assert "T2" in tasklist.render(tasklist.load(p))           # a fresh load (a context reset) still has it


def test_doing_done_drop_and_render_order(tmp_path):
    p = tmp_path / "w1.json"
    for t in ("a", "b", "c"):
        _apply(p, "add", t)
    _apply(p, "doing", task_id=2)
    _apply(p, "done", task_id=1)
    _apply(p, "drop", task_id=3)
    text = tasklist.render(tasklist.load(p))
    assert "T2 [doing] b" in text and "T1 [done] a" in text and "T3" not in text
    assert text.index("T2") < text.index("T1")                 # open tasks first, then recent done


def test_unknown_id_and_missing_text_are_reported(tmp_path):
    p = tmp_path / "w1.json"
    assert "no task" in _apply(p, "done", task_id=9).lower()
    assert "text" in _apply(p, "add").lower()
    assert "unknown op" in _apply(p, "zap").lower()


def test_limits_keep_the_list_small(tmp_path):
    p = tmp_path / "w1.json"
    for i in range(tasklist.MAX_OPEN):
        _apply(p, "add", f"t{i}")
    assert "full" in _apply(p, "add", "one too many").lower()
    out = _apply(p, "done", task_id=1) and _apply(p, "add", "x" * 500)
    assert "x" * tasklist.TEXT_CHARS in out and "x" * (tasklist.TEXT_CHARS + 1) not in out
    for i in range(2, 10):
        _apply(p, "done", task_id=i)
    done_lines = [line for line in tasklist.render(tasklist.load(p)).splitlines() if "[done]" in line]
    assert len(done_lines) <= tasklist.KEEP_DONE


def test_empty_list_renders_a_hint(tmp_path):
    assert "no tasks" in tasklist.render(tasklist.load(tmp_path / "nope.json")).lower()


def test_corrupt_file_starts_empty(tmp_path):
    p = tmp_path / "w1.json"
    p.write_text("{not json", encoding="utf-8")
    assert tasklist.load(p)["items"] == []
