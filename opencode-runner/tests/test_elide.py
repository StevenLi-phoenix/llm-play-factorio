import json
from types import SimpleNamespace

from agent import KEEP_TAIL, Agent, compact_args


def test_short_args_untouched():
    a = json.dumps({"radius": 20})
    assert compact_args(a) == a


def test_long_list_truncated_but_valid_json():
    steps = [{"type": "walk_to", "x": i, "y": i} for i in range(40)]
    out = compact_args(json.dumps({"steps": steps, "note": "x"}))
    parsed = json.loads(out)
    assert parsed["steps"] == steps[:2]
    assert parsed["note"] == "x"
    assert "_elided" not in out
    assert len(out) < 500


def test_unparseable_long_args_left_alone():
    bad = '{"steps": [' + "1," * 400
    assert compact_args(bad) == bad


def test_elide_never_writes_placeholder_arguments():
    steps = [{"type": "walk_to", "x": i, "y": i} for i in range(40)]
    call = {"id": "c1", "type": "function", "function": {"name": "run_plan", "arguments": json.dumps({"steps": steps})}}
    history = [{"role": "assistant", "content": "", "tool_calls": [call]}] + [
        {"role": "user", "content": "pad"} for _ in range(KEEP_TAIL + 2)]
    fake = SimpleNamespace(history=history, m={"shrinks": 0})
    Agent._elide(fake)
    args = json.loads(history[0]["tool_calls"][0]["function"]["arguments"])
    assert "_elided" not in args and len(args["steps"]) == 2
