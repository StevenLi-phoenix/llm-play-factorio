"""board_update: a running worker is told when board.md changes (workers almost never call board_read)."""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import agent  # noqa: E402


def test_unchanged_board_is_not_pushed(tmp_path):
    bp = tmp_path / "board.md"
    bp.write_text("PHASE: x", encoding="utf-8")
    text, seen = agent.board_update(bp, 0.0)
    assert text == "PHASE: x" and seen > 0
    assert agent.board_update(bp, seen) == (None, seen)


def test_changed_board_is_pushed_once(tmp_path):
    bp = tmp_path / "board.md"
    bp.write_text("old", encoding="utf-8")
    _, seen = agent.board_update(bp, 0.0)
    bp.write_text("new directives", encoding="utf-8")
    os.utime(bp, (seen + 5, seen + 5))
    text, seen2 = agent.board_update(bp, seen)
    assert text == "new directives" and seen2 == seen + 5
    assert agent.board_update(bp, seen2)[0] is None


def test_missing_board_is_quiet(tmp_path):
    assert agent.board_update(tmp_path / "nope.md", 3.0) == (None, 3.0)
