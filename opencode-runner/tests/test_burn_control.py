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
    return SimpleNamespace(deadline=time.time() + hours_left * 3600, samples=samples, agents=agents, paused_reason={}, burn_changed_at=0.0)


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


def test_resume_releases_one_agent_at_a_time():
    now = time.time()
    s = _sup([(now - 4 * 3600 + i * 3000, 60) for i in range(5)])
    for a in s.agents[2:]:
        a.paused = True
    s.paused_reason = {"w3": "burn control", "w4": "burn control"}
    run.Supervisor.control_burn(s, 60)
    assert [a.paused for a in s.agents] == [False, False, False, True]
    assert s.paused_reason == {"w4": "burn control"}


def test_samples_before_the_last_change_are_ignored():
    """After a pause the 6 h average still holds the old high burn; only samples since the change count."""
    now = time.time()
    old = [(now - 7 * 3600 + i * 600, 40 + i // 6) for i in range(12)]             # fast burn before the change
    new = [(now - 3.5 * 3600 + i * 3000, 55) for i in range(5)]                    # flat since the change
    s = _sup(old + new)
    s.burn_changed_at = now - 3.6 * 3600
    s.agents[3].paused = True
    s.paused_reason = {"w4": "burn control"}
    run.Supervisor.control_burn(s, 55)
    assert not s.agents[3].paused
    assert s.burn_changed_at > now - 5            # the resume is itself a change


def test_hold_after_a_change_until_enough_samples():
    now = time.time()
    s = _sup([(now - 1 * 3600 + i * 600, 50) for i in range(6)])
    s.burn_changed_at = now - 1.1 * 3600
    s.agents[3].paused = True
    s.paused_reason = {"w4": "burn control"}
    run.Supervisor.control_burn(s, 50)
    assert s.agents[3].paused
