"""Live output of one agent: every thought, message, tool call and result goes to `<root>/stream/<name>.jsonl`
(one JSON object per line) so the dashboard can push it to the browser as it happens. Append-only, never read
back by the agent itself."""
from __future__ import annotations

import json
import time
from pathlib import Path

CAPS = {"think": 12000, "say": 4000, "call": 2000, "result": 3000, "note": 1000, "error": 3000, "usage": 300}


class StreamWriter:
    def __init__(self, root: Path, name: str):
        self.name = name
        self.path = Path(root) / "stream" / f"{name}.jsonl"

    def emit(self, kind: str, text: str, turn: int = 0) -> None:
        text = (text or "").strip()
        if not text:
            return
        cap = CAPS.get(kind, 2000)
        if len(text) > cap:
            text = text[:cap] + f"\n...[{len(text) - cap} chars cut]"
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with self.path.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps({"ts": time.time(), "agent": self.name, "turn": turn, "kind": kind,
                                     "text": text}, ensure_ascii=False) + "\n")
        except OSError:
            pass  # the live view is best effort; it must never stop an agent
