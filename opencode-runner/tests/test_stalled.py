"""Supervisor watchdog: which agents have stopped taking turns."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import run  # noqa: E402


def test_stalled_lists_only_agents_that_should_be_working():
    rows = {"w1": {"paused": False, "fatal": "", "last_turn": 1000.0},   # no turn for 700 s: stalled
            "w2": {"paused": False, "fatal": "", "last_turn": 1600.0},   # recent
            "w3": {"paused": True, "fatal": "", "last_turn": 100.0},     # paused on purpose
            "w4": {"paused": False, "fatal": "", "last_turn": 0.0},      # not started yet
            "w5": {"paused": False, "fatal": "boom", "last_turn": 100.0}}
    assert run.stalled(rows, now_ts=1700.0) == ["w1"]
