"""Supervisor.trend_line: the coach's view of progress over the last ~30 minutes."""
import collections
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import run  # noqa: E402


def _sup(samples):
    return SimpleNamespace(kpi_hist=collections.deque(samples, maxlen=90))


def _k(progress, packs, bld):
    return {"research": "logistics-2", "progress": progress, "done": 9, "counts": {"lab": bld},
            "produced": {"automation-science-pack": packs}, "problems": {"no_fuel": 3}}


def test_not_enough_samples():
    assert "not enough" in run.Supervisor.trend_line(_sup([]))


def test_flat_progress_is_visible():
    s = _sup([(0, _k(0.0, 359, 4)), (1500, _k(0.0, 359, 4))])
    line = run.Supervisor.trend_line(s)
    assert "0% -> logistics-2 0%" in line and "'automation-science-pack': 0" in line and "buildings 4 -> 4" in line


def test_window_picks_sample_within_30_minutes():
    s = _sup([(0, _k(0.1, 100, 1)), (3000, _k(0.2, 200, 2)), (4000, _k(0.5, 260, 5))])
    line = run.Supervisor.trend_line(s)
    assert "last 17 min" in line and "'automation-science-pack': 60" in line
