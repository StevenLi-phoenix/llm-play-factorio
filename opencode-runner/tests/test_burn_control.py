"""Supervisor.control_burn: pause one agent only on a real overspend, ignore integer-rounding noise."""
import sys
import time
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import run  # noqa: E402


class FakeAgent:
    def __init__(self, name):
        self.name, self.paused = name, False

    def pause(self):
        self.paused = True

    def resume(self):
        self.paused = False


def _sup(samples, hours_left=30.0):
    agents = [FakeAgent(f"w{i}") for i in range(1, 5)]
    return SimpleNamespace(deadline=time.time() + hours_left * 3600, samples=samples, agents=agents, paused_reason={})


def test_short_span_is_ignored():
    now = time.time()
    s = _sup([(now - 3600 * (1.3 - i * 0.3), 61 + i // 2) for i in range(5)])
    run.Supervisor.control_burn(s, 63)
    assert not any(a.paused for a in s.agents)


def test_rounding_noise_does_not_pause():
    now = time.time()
    # 61 -> 63 over 3.2 h: nominal 0.62%/h, rounding-discounted 0.31%/h; 37% remain over 30 h
    s = _sup([(now - 3.2 * 3600 + i * 3000, 61) for i in range(4)])
    run.Supervisor.control_burn(s, 63)
    assert not any(a.paused for a in s.agents)


def test_real_overspend_pauses_the_last_agent():
    now = time.time()
    s = _sup([(now - 4 * 3600 + i * 3000, 20) for i in range(5)])      # 20 -> 60 in 4 h = 10%/h, 40% remain
    run.Supervisor.control_burn(s, 60)
    assert [a.paused for a in s.agents] == [False, False, False, True]
    assert s.paused_reason == {"w4": "burn control"}


def test_resumes_when_underspending():
    now = time.time()
    s = _sup([(now - 4 * 3600 + i * 3000, 60) for i in range(5)])      # flat -> projected 0
    s.agents[3].paused = True
    s.paused_reason = {"w4": "burn control"}
    run.Supervisor.control_burn(s, 60)
    assert not s.agents[3].paused and s.paused_reason == {}
