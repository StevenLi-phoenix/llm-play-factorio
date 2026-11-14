"""Supervisor: runs N opencode-go workers + a coach against the Factorio server, paces them to the OpenCode quota,
keeps the game at the target speed, and stops at the deadline (the OpenCode monthly reset) or when quota is gone.

Env: RUNNER_ROOT, FACTORIO_RCON_PORT/PASSWORD, LLMGW_API_KEY (+LLMGW_BASE), WORKER_MODELS (comma list, one per worker),
COACH_MODEL, DEADLINE (ISO UTC; default = the monthly resetsAt seen at start), GAME_SPEED, COACH_MINUTES.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from factorio_mcp.rcon import RconClient

from agent import Agent, RunCfg
from llm import Gateway, GatewayBadRequest, GatewayFatal
from prompts import COACH_SYSTEM

log = logging.getLogger("runner")

KPI_LUA = r"""
local f = game.forces.player
local s = game.surfaces.nauvis
local out = {tick = game.tick, speed = game.speed, research = f.current_research and f.current_research.name or nil,
  progress = f.research_progress, queue = {}, done = 0, counts = {}, problems = {}, produced = {}, chars = {}}
for _, t in pairs(f.research_queue) do out.queue[#out.queue+1] = t.name end
for _, t in pairs(f.technologies) do if t.researched and t.enabled then out.done = out.done + 1 end end
local probs = {[defines.entity_status.no_fuel]="no_fuel", [defines.entity_status.no_power]="no_power",
  [defines.entity_status.low_power]="low_power", [defines.entity_status.no_ingredients]="no_ingredients",
  [defines.entity_status.waiting_for_space_in_destination]="output_blocked", [defines.entity_status.no_minable_resources]="depleted"}
for _, e in pairs(s.find_entities_filtered{force = f}) do
  if e.type == "character" then out.chars[#out.chars+1] = {e.name_tag or "", math.floor(e.position.x), math.floor(e.position.y)}
  else
    out.counts[e.name] = (out.counts[e.name] or 0) + 1
    local st = e.status and probs[e.status]
    if st then out.problems[st] = (out.problems[st] or 0) + 1 end
  end
end
local stats = f.get_item_production_statistics(s)
for _, item in pairs({"iron-plate","copper-plate","steel-plate","coal","iron-gear-wheel","electronic-circuit","automation-science-pack",
  "logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack","space-science-pack",
  "plastic-bar","advanced-circuit","processing-unit","rocket-part"}) do
  local n = stats.get_input_count(item)
  if n > 0 then out.produced[item] = n end
end
rcon.print(helpers.table_to_json(out))"""


def now() -> float:
    return time.time()


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s: str) -> float:
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


class Supervisor:
    def __init__(self):
        e = os.environ
        self.root = Path(e.get("RUNNER_ROOT", str(Path.home() / "factorio-agent/state")))
        self.root.mkdir(parents=True, exist_ok=True)
        self.rcon = dict(host=e.get("FACTORIO_RCON_HOST", "127.0.0.1"), port=int(e.get("FACTORIO_RCON_PORT", "27017")),
                         pw=e["FACTORIO_RCON_PASSWORD"])
        self.gw = Gateway(e.get("LLMGW_BASE", "https://api.lishuyu.app/llm"), e["LLMGW_API_KEY"], self.root / "raw")
        models = [m.strip() for m in e.get("WORKER_MODELS", "deepseek-v4.1-flash").split(",") if m.strip()]
        cfg = RunCfg(root=self.root, rcon_host=self.rcon["host"], rcon_port=self.rcon["port"], rcon_password=self.rcon["pw"],
                     high_tokens=int(e.get("HIGH_TOKENS", "42000")))
        self.agents = [Agent(f"w{i+1}", f"w{i+1}", m, cfg, self.gw) for i, m in enumerate(models)]
        self.coach_model = e.get("COACH_MODEL", "deepseek-v4-pro")
        self.coach_every = float(e.get("COACH_MINUTES", "25")) * 60
        self.speed = float(e.get("GAME_SPEED", "1"))
        self.deadline = parse_iso(e["DEADLINE"]) if e.get("DEADLINE") else None
        self.stop = asyncio.Event()
        self.quota: dict | None = None
        self.samples: list[tuple[float, int]] = []        # (ts, monthly percent)
        self.kpi: dict | None = None
        self.ups = 0.0
        self.paused_reason: dict[str, str] = {}
        self.started = now()
        self.quota_start_pct: int | None = None

    # ---------- RCON helpers ----------
    async def rcon_exec(self, cmd: str) -> str:
        c = RconClient(self.rcon["host"], self.rcon["port"], self.rcon["pw"], 20.0)
        try:
            await c.connect()
            return await c.exec(cmd)
        finally:
            c.close()

    async def read_kpi(self) -> dict | None:
        try:
            raw = await self.rcon_exec("/silent-command " + " ".join(KPI_LUA.split("\n")))
            return json.loads(raw)
        except Exception as ex:  # noqa: BLE001
            log.warning("kpi read failed: %s", ex)
            return None

    # ---------- loops ----------
    async def game_loop(self) -> None:
        last_tick, last_wall = None, None
        while not self.stop.is_set():
            k = await self.read_kpi()
            if k:
                self.kpi = k
                if last_tick is not None and now() > last_wall:
                    self.ups = (k["tick"] - last_tick) / (now() - last_wall)
                last_tick, last_wall = k["tick"], now()
                with (self.root / "kpi.jsonl").open("a") as fh:
                    fh.write(json.dumps({**k, "wall": iso(now()), "ups": round(self.ups, 1)}) + "\n")
                if abs(k.get("speed", 1) - self.speed) > 0.01:
                    await self.rcon_exec(f"/silent-command game.speed = {self.speed}")
                    log.info("game speed %s -> %s", k.get("speed"), self.speed)
            await self._sleep(60)

    async def _sleep(self, s: float) -> None:
        try:
            await asyncio.wait_for(self.stop.wait(), s)
        except asyncio.TimeoutError:
            pass

    def monthly(self) -> tuple[int, str, float | None]:
        m = ((self.quota or {}).get("usage") or {}).get("monthly") or {}
        return int(m.get("percent", 0) or 0), m.get("status", "?"), (parse_iso(m["resetsAt"]) if m.get("resetsAt") else None)

    async def quota_loop(self) -> None:
        paused_all = False
        last_ctl = now()
        while not self.stop.is_set():
            q = await self.gw.quota()
            if q:
                self.quota = q
                pct, status, reset = self.monthly()
                if self.deadline is None and reset:
                    self.deadline = reset
                if self.quota_start_pct is None:
                    self.quota_start_pct = pct
                self.samples.append((now(), pct))
                self.samples = [s for s in self.samples if s[0] > now() - 6 * 3600]
                u = q["usage"]
                roll = u.get("rolling") or {}
                if status != "ok" or pct >= 100:
                    log.error("monthly quota exhausted (status=%s pct=%s): stopping", status, pct)
                    self.stop.set()
                    break
                hot = (roll.get("percent", 0) or 0) >= 92 or (u.get("weekly") or {}).get("percent", 0) >= 98
                if hot and not paused_all:
                    paused_all = True
                    for a in self.agents:
                        a.gate.clear()
                    log.warning("rolling/weekly quota hot (%s): pausing all agents", {k: v.get("percent") for k, v in u.items()})
                elif paused_all and (roll.get("percent", 0) or 0) < 70 and (u.get("weekly") or {}).get("percent", 0) < 98:
                    paused_all = False
                    for a in self.agents:
                        if a.name not in self.paused_reason:
                            a.gate.set()
                    log.info("quota recovered: resuming agents")
                if not paused_all and now() - last_ctl > 15 * 60:
                    last_ctl = now()
                    self.control_burn(pct)
            if self.deadline and now() >= self.deadline:
                log.info("deadline %s reached: stopping", iso(self.deadline))
                self.stop.set()
                break
            await self._sleep(120)

    def control_burn(self, pct: int) -> None:
        """Keep monthly burn on track to land at ~100% at the deadline: pause/resume agents."""
        if not self.deadline or len(self.samples) < 4:
            return
        hours_left = max((self.deadline - now()) / 3600, 0.05)
        t0, p0 = self.samples[0]
        span = (now() - t0) / 3600
        if span < 0.75:
            return
        rate = (pct - p0) / span                       # percent per hour (coarse: 1% resolution)
        remaining = 100 - pct
        projected = rate * hours_left
        active = [a for a in self.agents if a.gate.is_set()]
        log.info("burn: pct=%d rate=%.2f%%/h hours_left=%.1f projected=%.1f%% remaining=%d%% active=%d/%d",
                 pct, rate, hours_left, projected, remaining, len(active), len(self.agents))
        if projected > remaining * 1.15 and len(active) > 1:
            a = active[-1]
            a.gate.clear()
            self.paused_reason[a.name] = "burn control"
            log.warning("burn control: pausing %s", a.name)
        elif projected < remaining * 0.6:
            for a in self.agents:
                if self.paused_reason.get(a.name) == "burn control":
                    del self.paused_reason[a.name]
                    a.gate.set()
                    log.info("burn control: resuming %s", a.name)
                    break

    async def coach_loop(self) -> None:
        await self._sleep(min(self.coach_every, 20 * 60))
        while not self.stop.is_set():
            try:
                await self.run_coach()
            except GatewayFatal as e:
                log.error("coach fatal: %s", e)
            except Exception:  # noqa: BLE001
                log.exception("coach failed")
            await self._sleep(self.coach_every)

    async def run_coach(self) -> None:
        k = self.kpi or await self.read_kpi() or {}
        t = k.get("tick", 0) // 60
        lines = [f"game time {t // 3600}:{t // 60 % 60:02d}  tick {k.get('tick')}  speed {k.get('speed')}  ups {self.ups:.0f}",
                 f"research: {k.get('research')} {float(k.get('progress') or 0):.0%}; queue {k.get('queue')}; techs done {k.get('done')}",
                 f"produced totals: {k.get('produced')}", f"buildings: {dict(sorted((k.get('counts') or {}).items(), key=lambda kv: -kv[1])[:30])}",
                 f"problems: {k.get('problems')}", f"characters: {k.get('chars')}"]
        for a in self.agents:
            sf = self.root / "status" / f"{a.name}.txt"
            nf = self.root / "notes" / f"{a.name}.md"
            lines.append(f"--- {a.name} ({a.model}) turns={a.m['turns']} tool_errors={a.m['tool_errors']} paused={not a.gate.is_set()}")
            lines.append("status: " + (sf.read_text()[:200] if sf.exists() else "(none)"))
            lines.append("notes: " + (nf.read_text()[:1200] if nf.exists() else "(none)"))
        prev = (self.root / "board.md")
        lines.append("--- previous board:\n" + (prev.read_text()[:2500] if prev.exists() else "(none)"))
        r = await self.gw.chat(agent="coach", model=self.coach_model, session="coach", tools=None, max_tokens=2500,
                               messages=[{"role": "system", "content": COACH_SYSTEM}, {"role": "user", "content": "\n".join(lines)}])
        text = (r["choices"][0]["message"].get("content") or "").strip()
        if text:
            prev.write_text(f"[board updated {iso(now())}]\n{text[:3500]}\n", encoding="utf-8")
            log.info("coach wrote board (%d chars)", len(text))

    async def report_loop(self) -> None:
        while not self.stop.is_set():
            pct, status, reset = self.monthly()
            data = {"ts": iso(now()), "started": iso(self.started), "deadline": iso(self.deadline) if self.deadline else None,
                    "quota": (self.quota or {}).get("usage"), "key": (self.quota or {}).get("key"), "monthly_start_pct": self.quota_start_pct,
                    "gateway": self.gw.stats, "ups": round(self.ups, 1), "kpi": self.kpi,
                    "agents": {a.name: {**a.m, "model": a.model, "paused": not a.gate.is_set(), "fatal": a.fatal} for a in self.agents}}
            (self.root / "runner.json").write_text(json.dumps(data), encoding="utf-8")
            await self._sleep(30)

    async def main(self) -> None:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, self.stop.set)
        q = await self.gw.quota()
        if q:
            self.quota = q
            self.quota_start_pct = self.monthly()[0]
            if self.deadline is None and self.monthly()[2]:
                self.deadline = self.monthly()[2]
        log.info("start: workers=%s coach=%s speed=%s deadline=%s quota=%s", [(a.name, a.model) for a in self.agents],
                 self.coach_model, self.speed, self.deadline and iso(self.deadline), (q or {}).get("usage"))
        tasks = [asyncio.create_task(self.quota_loop()), asyncio.create_task(self.game_loop()),
                 asyncio.create_task(self.coach_loop()), asyncio.create_task(self.report_loop())]
        for i, a in enumerate(self.agents):
            tasks.append(asyncio.create_task(self._start_agent(a, i * 15)))
        await self.stop.wait()
        log.info("stopping agents")
        for a in self.agents:
            a.stop.set()
            a.gate.set()
        await asyncio.wait(tasks, timeout=30)
        for t in tasks:
            t.cancel()

    async def _start_agent(self, a: Agent, delay: float) -> None:
        await asyncio.sleep(delay)
        await a.run_forever()
        if a.fatal:
            log.error("agent %s ended: %s", a.name, a.fatal)


def main() -> None:
    root = Path(os.environ.get("RUNNER_ROOT", str(Path.home() / "factorio-agent/state")))
    (root / "logs").mkdir(parents=True, exist_ok=True)
    fmt = "%(asctime)s %(levelname)s %(name)s %(message)s"
    logging.basicConfig(level=logging.INFO, format=fmt, handlers=[logging.StreamHandler(sys.stderr),
                                                                  logging.FileHandler(root / "logs" / "runner.log")])
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("factorio_mcp").setLevel(logging.WARNING)
    asyncio.run(Supervisor().main())


if __name__ == "__main__":
    main()
