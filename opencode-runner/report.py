"""One-screen status of a running supervisor (reads RUNNER_ROOT/runner.json). Stdlib only.
  python3 report.py [--logs N]   # N = tail lines of each agent log"""
import json
import os
import sys
import time
from pathlib import Path

root = Path(os.environ.get("RUNNER_ROOT", Path.home() / "factorio-agent/state"))
try:
    d = json.loads((root / "runner.json").read_text())
except FileNotFoundError:
    sys.exit("no runner.json (supervisor not started?)")
age = time.time() - (root / "runner.json").stat().st_mtime
if "--oneline" in sys.argv:
    kp = d.get("kpi") or {}
    t = (kp.get("tick") or 0) // 60
    u = d.get("quota") or {}
    ag = " | ".join(f"{n} t{a['turns']} e{a['tool_errors']} nt{a['no_tool']} idle{(time.time() - a['last_turn']) if a['last_turn'] else -1:.0f}s{' PAUSED' if a['paused'] else ''}"
                    for n, a in d["agents"].items())
    k = d.get("key") or {}
    print(f"game {t // 3600}:{t // 60 % 60:02d} ups {d['ups']} res {kp.get('research')} {float(kp.get('progress') or 0):.0%} done {kp.get('done')} "
          f"bld {sum((kp.get('counts') or {}).values())} | {ag} | quota m{(u.get('monthly') or {}).get('percent')} r{(u.get('rolling') or {}).get('percent')} "
          f"w{(u.get('weekly') or {}).get('percent')} key ${k.get('spend_usd')} age{age:.0f}s")
    sys.exit(0)
u = d.get("quota") or {}
print(f"runner.json age {age:.0f}s  started {d['started']}  deadline {d['deadline']}")
print("quota:", {k: f"{v.get('percent')}% reset {v.get('resetsAt')}" for k, v in u.items()}, " monthly at start:", d.get("monthly_start_pct"))
k = d.get("key") or {}
print(f"gateway key: spent ${k.get('spend_usd')} remaining ${k.get('remaining_usd')} | reqs {d['gateway']}")
kp = d.get("kpi") or {}
if kp:
    t = kp["tick"] // 60
    print(f"game {t // 3600}:{t // 60 % 60:02d} ups {d['ups']} speed {kp.get('speed')} | research {kp.get('research')} {float(kp.get('progress') or 0):.0%} done {kp.get('done')}")
    print("produced:", kp.get("produced"), "| problems:", kp.get("problems"))
    c = kp.get("counts") or {}
    print("buildings:", dict(sorted(c.items(), key=lambda kv: -kv[1])[:14]))
for n, a in d["agents"].items():
    idle = time.time() - a["last_turn"] if a["last_turn"] else -1
    print(f"{n} {a['model']}: turns {a['turns']} calls {a['tool_calls']} err {a['tool_errors']} notool {a['no_tool']} bad {a['bad']} "
          f"prompt {a['prompt']} cached {a['cached']} compl {a['completion']} lastp {a['last_prompt']} shrink {a['shrinks']} sum {a['summaries']} "
          f"sess {a['sessions']} idle {idle:.0f}s paused {a['paused']} fatal {a['fatal']}")
    sf = root / "status" / f"{n}.txt"
    if sf.exists():
        print("   status:", sf.read_text().strip()[:200])
if "--logs" in sys.argv:
    nlog = int(sys.argv[sys.argv.index("--logs") + 1])
    for n in d["agents"]:
        lf = root / "logs" / f"{n}.log"
        if lf.exists():
            print(f"--- {n}.log")
            print("\n".join(l[:230] for l in lf.read_text().splitlines()[-nlog:]))
