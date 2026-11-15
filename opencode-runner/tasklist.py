"""Persistent per-agent task list. An agent's context is reset every ~40 minutes and `notes_set` overwrites the whole
note, so what it was doing is easily lost; this list is changed one item at a time, lives in state/tasks/<name>.json,
is shown again at every context start and is visible to the coach."""
from __future__ import annotations

import json
import logging
from pathlib import Path

log = logging.getLogger("tasklist")

MAX_OPEN = 12     # open (todo + doing) tasks per agent
TEXT_CHARS = 160  # characters kept per task
KEEP_DONE = 3     # finished tasks kept for context
OPS = ("add", "doing", "done", "drop", "list")


def load(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data.get("items"), list):
            return {"next_id": int(data.get("next_id", 1)), "items": data["items"]}
    except FileNotFoundError:
        pass
    except (OSError, ValueError, AttributeError) as e:
        log.warning("task list %s unreadable, starting empty: %s", path, e)
    return {"next_id": 1, "items": []}


def save(path: Path, data: dict) -> None:
    done = [i for i in data["items"] if i["status"] == "done"][-KEEP_DONE:]
    data["items"] = [i for i in data["items"] if i["status"] != "done"] + done
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def render(data: dict) -> str:
    items = data["items"]
    if not items:
        return "(no tasks yet: tasks(op='add', text=...) keeps your plan across context resets)"
    order = {"doing": 0, "todo": 1, "done": 2}
    lines = [f"T{i['id']} [{i['status']}] {i['text']}" for i in sorted(items, key=lambda i: (order[i["status"]], i["id"]))]
    return "\n".join(lines)


def apply(path: Path, op: str, text: str | None = None, task_id: int | None = None) -> str:
    """Run one operation on the list stored at `path`; returns the new list, or the reason it was refused."""
    if op not in OPS:
        return f"unknown op {op!r}: use one of {', '.join(OPS)}"
    data = load(path)
    if op == "list":
        return render(data)
    if op == "add":
        if not text or not str(text).strip():
            return "add needs text"
        if sum(1 for i in data["items"] if i["status"] != "done") >= MAX_OPEN:
            return f"list full ({MAX_OPEN} open tasks): finish or drop one first\n{render(data)}"
        data["items"].append({"id": data["next_id"], "text": str(text).strip()[:TEXT_CHARS], "status": "todo"})
        data["next_id"] += 1
    else:
        item = next((i for i in data["items"] if i["id"] == task_id), None)
        if item is None:
            return f"no task T{task_id}\n{render(data)}"
        if op == "drop":
            data["items"].remove(item)
        else:
            item["status"] = "doing" if op == "doing" else "done"
    save(path, data)
    return render(data)
