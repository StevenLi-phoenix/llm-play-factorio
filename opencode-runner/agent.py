"""One LLM worker driving one Factorio character through the in-process factorio-mcp tools."""
from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass
from pathlib import Path

from factorio_mcp.game import Config as GameConfig
from factorio_mcp.server import build_app

from llm import Gateway, GatewayBadRequest, GatewayFatal
from prompts import COMPACT_PROMPT, NUDGE, NUDGE_CUT, START_MSG, WORKER_SYSTEM

LOG_OK_CHARS, LOG_ERR_CHARS = 160, 500   # tool output chars logged; errors keep the failing reason
KEEP_TAIL = 14           # messages never elided
HIGH_TOKENS = 42_000      # prompt tokens that trigger a shrink
MAX_RESULT_CHARS = 5_500  # per tool result
MAX_TOOL_CALLS_PER_TURN = 8
RESTART_BACKOFF, RESTART_BACKOFF_MAX = 10, 300   # seconds between crashed-session restarts (doubles up to the max)


def parse_tool_args(raw: str | None):
    """json.loads, but when a model appends text after the first JSON value ("Extra data") keep the first value."""
    text = raw or "{}"
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        if not e.msg.startswith("Extra data"):
            raise
        value, _ = json.JSONDecoder().raw_decode(text.lstrip())
        return value


@dataclass
class RunCfg:
    root: Path                       # state dir (notes, status, logs, board)
    rcon_host: str
    rcon_port: int
    rcon_password: str
    high_tokens: int = HIGH_TOKENS
    max_result_chars: int = MAX_RESULT_CHARS
    max_tokens: int = 6000


def _slim(node):
    """Shrink a JSON schema: drop titles, cut descriptions, collapse Optional anyOf."""
    if isinstance(node, list):
        return [_slim(x) for x in node]
    if not isinstance(node, dict):
        return node
    if "anyOf" in node:
        alts = [a for a in node["anyOf"] if a.get("type") != "null"]
        if len(alts) == 1:
            merged = {k: v for k, v in node.items() if k != "anyOf"}
            merged.update(alts[0])
            return _slim(merged)
    out = {}
    for k, v in node.items():
        if k == "title":
            continue
        if k == "properties" and isinstance(v, dict):
            out[k] = {pk: _slim(pv) for pk, pv in v.items()}
        elif k == "description" and isinstance(v, str):
            out[k] = v if len(v) <= 110 else v[:107].rstrip() + "..."
        else:
            out[k] = _slim(v)
    return out


def _short_desc(d: str, limit: int = 260, tail_limit: int = 120) -> str:
    """Shrink a tool description for the schema. The last clause usually holds the argument caveats
    (e.g. analyze_factory "(no x/y)"), so a short final clause is kept after the cut."""
    d = " ".join((d or "").split())
    if len(d) <= limit:
        return d
    cut = d[:limit]
    i = max(cut.rfind(". "), cut.rfind("; "))
    head = cut[: i + 1] if i > 80 else cut.rstrip()
    j = max(d[:-1].rfind(". "), d[:-1].rfind("; "))
    tail = d[j + 2:] if j >= 0 else ""
    if tail and len(tail) <= tail_limit and j + 2 > len(head):
        head = f"{head} ... {tail}"
    return head + " (tool_help for more)"


def compact_args(a: str, keep: int = 2) -> str:
    """Shrink old tool-call arguments while keeping them valid JSON of the same shape (long lists keep their
    first `keep` items). A `{"_elided": ...}` placeholder used to be copied by the model into new calls."""
    try:
        obj = json.loads(a)
    except json.JSONDecodeError:
        return a
    if not isinstance(obj, dict):
        return a
    return json.dumps({k: (v[:keep] if isinstance(v, list) and len(v) > keep else v) for k, v in obj.items()})


LOCAL_TOOLS = [
    {"type": "function", "function": {"name": "notes_set", "description": "Overwrite your private notes (<=2000 chars). They survive context resets: keep current task, what exists with coordinates, what is broken, next steps.", "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}},
    {"type": "function", "function": {"name": "status_set", "description": "Publish one line (<=200 chars) about what you are doing/need, shown to the coach and other agents.", "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}},
    {"type": "function", "function": {"name": "board_read", "description": "Read the coach's board (phase, priorities, warnings) plus every agent's status line.", "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {"name": "tool_help", "description": "Full original description of a game tool.", "parameters": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}}},
]


class Agent:
    def __init__(self, name: str, character: str, model: str, cfg: RunCfg, gw: Gateway):
        self.name, self.character, self.model, self.cfg, self.gw = name, character, model, cfg, gw
        self.log = logging.getLogger(f"agent.{name}")
        self.stop = asyncio.Event()
        self.gate = asyncio.Event()
        self.gate.set()                       # cleared by the pacing controller
        self.fatal: str | None = None
        self.echo_reasoning = False
        self.history: list[dict] = []
        self.summary = ""
        self.m = dict(turns=0, tool_calls=0, tool_errors=0, prompt=0, completion=0, cached=0, sessions=0,
                      last_turn=0.0, last_prompt=0, shrinks=0, summaries=0, no_tool=0, bad=0, cut=0)
        self.last_tools: list[str] = []
        for d in ("notes", "status", "logs"):
            (cfg.root / d).mkdir(parents=True, exist_ok=True)
        if not self.log.handlers:   # one file per agent; the supervisor log stays readable
            fh = logging.FileHandler(cfg.root / "logs" / f"{name}.log", encoding="utf-8")
            fh.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
            self.log.addHandler(fh)
            self.log.propagate = False
            self.log.setLevel(logging.INFO)
        self._app = None
        self._full_desc: dict[str, str] = {}
        self.tools: list[dict] = []

    # ---------- public surface for the supervisor ----------
    @property
    def paused(self) -> bool:
        return not self.gate.is_set()

    def pause(self) -> None:
        self.gate.clear()

    def resume(self) -> None:
        self.gate.set()

    def summary_row(self) -> dict:
        """What runner.json / the dashboard show for this agent."""
        return {**self.m, "model": self.model, "paused": self.paused, "fatal": self.fatal}

    # ---------- files ----------
    def _p(self, kind: str, ext: str = "md") -> Path:
        return self.cfg.root / kind / f"{self.name}.{ext}"

    def read_notes(self) -> str:
        p = self._p("notes")
        return p.read_text(encoding="utf-8") if p.exists() else "(none yet)"

    def board_text(self) -> str:
        bp = self.cfg.root / "board.md"
        parts = [bp.read_text(encoding="utf-8") if bp.exists() else "(no board yet)"]
        for f in sorted((self.cfg.root / "status").glob("*.txt")):
            parts.append(f"[{f.stem}] {f.read_text(encoding='utf-8').strip()[:200]}")
        return "\n".join(parts)

    def write_metrics(self) -> None:
        self._p("status", "json").write_text(json.dumps({**self.m, "model": self.model, "character": self.character,
                                                         "last_tools": self.last_tools[-6:], "ts": time.time()}),
                                             encoding="utf-8")

    # ---------- tools ----------
    async def _setup_app(self) -> None:
        gc = GameConfig(host=self.cfg.rcon_host, port=self.cfg.rcon_port, password=self.cfg.rcon_password,
                        character=self.character, takeover=True)
        self._app = build_app(gc)
        self._hb = asyncio.create_task(self._app._game.heartbeat_loop())
        listed = await self._app.list_tools()
        tools = []
        for t in listed:
            self._full_desc[t.name] = t.description or ""
            tools.append({"type": "function", "function": {
                "name": t.name, "description": _short_desc(t.description), "parameters": _slim(t.input_schema)}})
        self.tools = tools + LOCAL_TOOLS

    async def _teardown_app(self) -> None:
        if getattr(self, "_hb", None):
            self._hb.cancel()
        if self._app is not None:
            try:
                await self._app._game.close()
            except Exception:  # noqa: BLE001
                pass
        self._app = None

    def _trim(self, text: str) -> str:
        n = self.cfg.max_result_chars
        if len(text) <= n:
            return text
        h = int(n * 0.72)
        return text[:h] + f"\n...[{len(text) - n} chars cut]...\n" + text[-(n - h):]

    async def _call(self, name: str, args: dict) -> str:
        if name == "notes_set":
            t = str(args.get("text", ""))[:2000]
            self._p("notes").write_text(t, encoding="utf-8")
            return f"notes saved ({len(t)} chars)"
        if name == "status_set":
            self._p("status", "txt").write_text(str(args.get("text", ""))[:200], encoding="utf-8")
            return "status published"
        if name == "board_read":
            return self.board_text()
        if name == "tool_help":
            return self._full_desc.get(str(args.get("name")), "unknown tool")[:3500]
        try:
            res = await asyncio.wait_for(self._app.call_tool(name, args), timeout=200)
        except asyncio.TimeoutError:
            return "ERROR: tool call timed out after 200s"
        except Exception as e:  # noqa: BLE001
            return f"ERROR: {type(e).__name__}: {e}"
        text = "\n".join(c.text for c in res.content if getattr(c, "text", None))
        return ("ERROR: " + text) if getattr(res, "is_error", False) else text

    # ---------- context management ----------
    def _elide(self) -> None:
        cut = len(self.history) - KEEP_TAIL
        for i, msg in enumerate(self.history[:max(cut, 0)]):
            if msg["role"] == "tool" and len(msg["content"]) > 300:
                msg["content"] = msg["content"][:260] + " ...[elided]"
            elif msg["role"] == "assistant":
                if msg.get("content") and len(msg["content"]) > 300:
                    msg["content"] = msg["content"][:300] + "..."
                msg.pop("reasoning_content", None)
                for tc in msg.get("tool_calls") or []:
                    a = tc["function"].get("arguments") or ""
                    if len(a) > 500:
                        tc["function"]["arguments"] = compact_args(a)
        self.m["shrinks"] += 1

    def _est_tokens(self) -> int:
        return int(sum(len(json.dumps(m)) for m in self.history) / 3.2) + 9000

    async def _summarize(self) -> None:
        msgs = [{"role": "system", "content": self._system()}] + self.history + [{"role": "user", "content": COMPACT_PROMPT}]
        try:
            r = await self.gw.chat(agent=self.name, model=self.model, messages=msgs, tools=self.tools, tool_choice="none",
                                   session=f"{self.name}-sum", max_tokens=1500)
            self.summary = (r["choices"][0]["message"].get("content") or "").strip()[:3500]
        except GatewayBadRequest as e:
            self.log.warning("summary failed (%s); keeping tail only", e)
            self.summary = "(summary unavailable; rely on notes and look around)"
        self._p("notes", "summary.md").write_text(self.summary, encoding="utf-8")
        self.m["summaries"] += 1
        self._reset_history()

    def _system(self) -> str:
        return WORKER_SYSTEM.format(character=self.character)

    def _reset_history(self) -> None:
        self.history = [{"role": "user", "content": START_MSG.format(
            character=self.character, notes=self.read_notes(), summary=self.summary or "(none)", board=self.board_text())}]

    # ---------- main loop ----------
    async def run_forever(self) -> None:
        backoff = RESTART_BACKOFF
        while not self.stop.is_set() and not self.fatal:
            try:
                await self._session()
                backoff = RESTART_BACKOFF
            except GatewayFatal as e:
                self.fatal = str(e)
                self.log.error("fatal gateway error: %s", e)
            except asyncio.CancelledError:
                raise
            except Exception:  # noqa: BLE001
                self.log.exception("session crashed; restarting in %ss", backoff)
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, RESTART_BACKOFF_MAX)
            finally:
                await self._teardown_app()

    async def _session(self) -> None:
        self.m["sessions"] += 1
        await self._setup_app()
        if not self.history:
            sp = self._p("notes", "summary.md")
            if not self.summary and sp.exists():
                self.summary = sp.read_text(encoding="utf-8")
            self._reset_history()
        consecutive_bad = 0
        while not self.stop.is_set():
            await self.gate.wait()
            try:
                r = await self.gw.chat(agent=self.name, model=self.model, session=self.name,
                                       messages=[{"role": "system", "content": self._system()}] + self.history,
                                       tools=self.tools, max_tokens=self.cfg.max_tokens)
                consecutive_bad = 0
            except GatewayBadRequest as e:
                consecutive_bad += 1
                self.m["bad"] += 1
                t = e.text.lower()
                self.log.warning("bad request #%d: %s", consecutive_bad, e)
                if "reasoning" in t and not self.echo_reasoning:
                    self.echo_reasoning = True
                elif any(w in t for w in ("context", "too long", "maximum", "token")):
                    self._elide()
                    await self._summarize()
                elif consecutive_bad >= 3:
                    self.history = []
                    self.summary = self.summary or "(restarted after repeated bad requests)"
                    self._reset_history()
                await asyncio.sleep(5)
                continue
            msg = r["choices"][0]["message"]
            u = r.get("usage") or {}
            self.m["turns"] += 1
            self.m["prompt"] += u.get("prompt_tokens", 0) or 0
            self.m["completion"] += u.get("completion_tokens", 0) or 0
            self.m["cached"] += ((u.get("prompt_tokens_details") or {}).get("cached_tokens", 0)) or 0
            self.m["last_prompt"] = u.get("prompt_tokens", 0) or 0
            self.m["last_turn"] = time.time()
            calls = msg.get("tool_calls") or []
            am: dict = {"role": "assistant", "content": msg.get("content") or ""}
            if calls:
                am["tool_calls"] = [{"id": c["id"], "type": "function",
                                     "function": {"name": c["function"]["name"], "arguments": c["function"].get("arguments") or "{}"}}
                                    for c in calls]
            if self.echo_reasoning and msg.get("reasoning_content"):
                am["reasoning_content"] = msg["reasoning_content"]
            self.history.append(am)
            if not calls:
                self.m["no_tool"] += 1
                self.log.info("T%d no tool call (%s) %s", self.m["turns"], r["choices"][0].get("finish_reason"), (msg.get("content") or "")[:120])
                cut = r["choices"][0].get("finish_reason") == "length"
                self.m["cut"] += int(cut)
                self.history.append({"role": "user", "content": NUDGE_CUT if cut else NUDGE})
            for i, c in enumerate(calls):
                name = c["function"]["name"]
                try:
                    args = parse_tool_args(c["function"].get("arguments"))
                    if not isinstance(args, dict):
                        raise ValueError("arguments must be a JSON object")
                except ValueError as e:
                    cut = r["choices"][0].get("finish_reason") == "length"
                    self.log.warning("T%d %s: invalid JSON arguments (%s)%s", self.m["turns"], name, e,
                                     " - reply was cut at max_tokens" if cut else "")
                    out = (f"ERROR: invalid JSON arguments ({e}). Send a JSON object."
                           + (" Your reply hit the output limit and was cut: think less and send shorter arguments." if cut else ""))
                else:
                    out = "skipped: too many tool calls in one turn, repeat it next turn" if i >= MAX_TOOL_CALLS_PER_TURN \
                        else self._trim(await self._call(name, args))
                self.m["tool_calls"] += 1
                if out.startswith("ERROR"):
                    self.m["tool_errors"] += 1
                self.last_tools.append(name)
                self.history.append({"role": "tool", "tool_call_id": c["id"], "content": out})
                self.log.info("T%d %s(%s) -> %s", self.m["turns"], name, c["function"].get("arguments", "")[:140],
                          out[:LOG_ERR_CHARS if out.startswith("ERROR") else LOG_OK_CHARS].replace("\n", " | "))
            self.log.info("T%d prompt=%s completion=%s ms=%s", self.m["turns"], u.get("prompt_tokens"), u.get("completion_tokens"), r.get("_ms"))
            self.write_metrics()
            if self.m["last_prompt"] > self.cfg.high_tokens:
                self._elide()
                if self._est_tokens() > self.cfg.high_tokens * 0.8 or len(self.history) > 160:
                    await self._summarize()
