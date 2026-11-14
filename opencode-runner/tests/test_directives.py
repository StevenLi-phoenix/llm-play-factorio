"""Supervisor directives: a human-set file that is always on top of the coach's board."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import run  # noqa: E402


def test_missing_file_gives_empty(tmp_path):
    assert run.read_directives(tmp_path) == ""


def test_reads_and_limits(tmp_path):
    (tmp_path / "directives.md").write_text("  1. fuel the boilers\n" + "x" * 5000, encoding="utf-8")
    out = run.read_directives(tmp_path)
    assert out.startswith("1. fuel the boilers") and len(out) == run.DIRECTIVES_CHARS


def test_compose_board_puts_directives_first():
    text = run.compose_board("2026-11-14T22:00:00Z", "1. fuel the boilers", "PHASE: x")
    assert text.startswith("[board updated 2026-11-14T22:00:00Z]\n")
    assert text.index("1. fuel the boilers") < text.index("PHASE: x")


def test_compose_board_without_directives_is_the_old_format():
    assert run.compose_board("T", "", "PHASE: x") == "[board updated T]\nPHASE: x\n"


def test_board_body_cuts_the_prepended_directives():
    board = run.compose_board("T", "1. fuel the boilers", "PHASE: x")
    assert run.board_body(board, "1. fuel the boilers") == "[board updated T]\nPHASE: x\n"
    assert run.board_body(board, "") == board
