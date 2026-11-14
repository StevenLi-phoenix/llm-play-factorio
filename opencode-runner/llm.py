"""OpenAI-compatible chat client for the LLM gateway (OpenCode Go models).

Every raw response body is appended to disk BEFORE it is parsed (paid API). Retries 429/5xx/timeouts with backoff;
401/402/403 raise GatewayFatal; other 4xx raise GatewayBadRequest so the caller can react (context too long, ...).
"""
from __future__ import annotations

import asyncio
import json
import logging
import random
import time
from pathlib import Path

import httpx

log = logging.getLogger("runner.llm")


class GatewayFatal(Exception):
    def __init__(self, status: int, text: str):
        super().__init__(f"HTTP {status}: {text[:300]}")
        self.status, self.text = status, text


class GatewayBadRequest(Exception):
    def __init__(self, status: int, text: str):
        super().__init__(f"HTTP {status}: {text[:500]}")
        self.status, self.text = status, text


class Gateway:
    def __init__(self, base: str, key: str, raw_dir: Path):
        self.base = base.rstrip("/")
        self.key = key
        self.raw_dir = raw_dir
        raw_dir.mkdir(parents=True, exist_ok=True)
        self.client = httpx.AsyncClient(timeout=httpx.Timeout(300, connect=20))
        self.stats = {"requests": 0, "errors": 0, "prompt": 0, "completion": 0, "cached": 0}

    def _raw(self, agent: str, status: int, text: str, ms: int, headers: dict) -> None:
        f = self.raw_dir / f"{agent}-{time.strftime('%Y%m%d', time.gmtime())}.jsonl"
        with f.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({"ts": time.time(), "status": status, "ms": ms, "h": headers, "body": text}) + "\n")

    async def chat(self, *, agent: str, model: str, messages: list, tools: list | None, session: str,
                   max_tokens: int = 4096, temperature: float | None = None,
                   tool_choice: str = "auto") -> dict:
        body: dict = {"model": model if "/" in model else f"opencode-go/{model}", "messages": messages,
                      "max_tokens": max_tokens}
        if tools:
            body["tools"] = tools
            body["tool_choice"] = tool_choice
        if temperature is not None:
            body["temperature"] = temperature
        headers = {"Authorization": f"Bearer {self.key}", "content-type": "application/json", "x-session-key": session}
        delay = 3.0
        for attempt in range(1, 9):
            t0 = time.monotonic()
            try:
                r = await self.client.post(f"{self.base}/v1/chat/completions", json=body, headers=headers)
            except (httpx.TimeoutException, httpx.TransportError) as e:
                self.stats["errors"] += 1
                log.warning("%s: transport error %s (attempt %d)", agent, type(e).__name__, attempt)
                await asyncio.sleep(delay + random.random())
                delay = min(delay * 2, 120)
                continue
            ms = int((time.monotonic() - t0) * 1000)
            hdr = {k: v for k, v in r.headers.items() if k.startswith("x-llm") or k == "retry-after"}
            self._raw(agent, r.status_code, r.text, ms, hdr)
            self.stats["requests"] += 1
            if r.status_code == 200:
                try:
                    data = r.json()
                    data["choices"][0]["message"]
                except (ValueError, KeyError, IndexError):
                    self.stats["errors"] += 1
                    await asyncio.sleep(delay)
                    continue
                u = data.get("usage") or {}
                self.stats["prompt"] += u.get("prompt_tokens", 0) or 0
                self.stats["completion"] += u.get("completion_tokens", 0) or 0
                self.stats["cached"] += ((u.get("prompt_tokens_details") or {}).get("cached_tokens", 0)) or 0
                data["_ms"] = ms
                return data
            self.stats["errors"] += 1
            if r.status_code in (401, 402, 403):
                raise GatewayFatal(r.status_code, r.text)
            if r.status_code == 429 or r.status_code >= 500:
                wait = float(r.headers.get("retry-after", delay))
                log.warning("%s: HTTP %d, retry in %.0fs (attempt %d) %s", agent, r.status_code, wait, attempt, r.text[:160])
                await asyncio.sleep(min(wait, 300) + random.random())
                delay = min(delay * 2, 120)
                continue
            raise GatewayBadRequest(r.status_code, r.text)
        raise RuntimeError("gateway: gave up after 8 attempts")

    async def quota(self) -> dict | None:
        try:
            r = await self.client.get(f"{self.base}/api/upstream/opencode-go/quota",
                                      headers={"Authorization": f"Bearer {self.key}"}, timeout=20)
            return r.json() if r.status_code == 200 else None
        except (httpx.HTTPError, ValueError):
            return None
