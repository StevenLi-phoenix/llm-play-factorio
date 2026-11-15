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


def test_trend_shows_upstream_items_of_the_green_chain():
    k0 = {"research": "x", "progress": 0.0, "done": 1, "counts": {"lab": 1},
          "produced": {"iron-plate": 100, "transport-belt": 10, "pipe": 5}, "problems": {}}
    k1 = {**k0, "produced": {"iron-plate": 400, "transport-belt": 10, "pipe": 9, "inserter": 4}}
    line = run.Supervisor.trend_line(_sup([(0, k0), (1500, k1)]))
    assert "'iron-plate': 300" in line and "'transport-belt': 0" in line and "pipe" not in line


def test_queue_with_packs_names_the_packs_each_tech_needs():
    assert run.queue_with_packs(["research-speed-3", "x"], {"research-speed-3": "automation+logistic+chemical"}) == \
        "research-speed-3 [automation+logistic+chemical], x"
    assert run.queue_with_packs([], {}) == "(empty)"
    assert run.queue_with_packs(None, None) == "(empty)"
