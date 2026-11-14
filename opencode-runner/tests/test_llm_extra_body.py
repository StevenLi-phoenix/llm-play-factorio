"""Gateway.extra_body: sent when set, dropped for good when the gateway rejects one of its keys."""
import asyncio
import json
import sys
import tempfile
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from llm import Gateway, GatewayBadRequest  # noqa: E402

OK = {"choices": [{"message": {"role": "assistant", "content": "hi"}, "finish_reason": "stop"}], "usage": {}}


def _gateway(handler, extra) -> Gateway:
    gw = Gateway("http://gw.test", "k", Path(tempfile.mkdtemp()), extra_body=extra)
    gw.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return gw


def _chat(gw: Gateway):
    return asyncio.run(gw.chat(agent="t", model="m", session="s", messages=[{"role": "user", "content": "x"}], tools=None))


def test_extra_body_is_sent():
    seen = []

    def handler(req):
        seen.append(json.loads(req.content))
        return httpx.Response(200, json=OK)

    _chat(_gateway(handler, {"reasoning_effort": "low"}))
    assert seen[0]["reasoning_effort"] == "low"


def test_rejected_extra_body_is_dropped_and_retried():
    seen = []

    def handler(req):
        body = json.loads(req.content)
        seen.append(body)
        if "reasoning_effort" in body:
            return httpx.Response(400, text="unknown field reasoning_effort")
        return httpx.Response(200, json=OK)

    gw = _gateway(handler, {"reasoning_effort": "low"})
    assert _chat(gw)["choices"][0]["message"]["content"] == "hi"
    assert gw.extra_body == {} and len(seen) == 2 and "reasoning_effort" not in seen[1]


def test_unrelated_400_still_raises_and_keeps_extra():
    gw = _gateway(lambda req: httpx.Response(400, text="context too long"), {"reasoning_effort": "low"})
    try:
        _chat(gw)
    except GatewayBadRequest:
        pass
    else:
        raise AssertionError("expected GatewayBadRequest")
    assert gw.extra_body == {"reasoning_effort": "low"}
