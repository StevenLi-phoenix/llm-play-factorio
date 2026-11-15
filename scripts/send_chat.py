#!/usr/bin/env python3
"""Post a line into the game chat as the supervisor (mod 0.3.13+ `post_chat`), optionally addressed to one agent.

    python3 -I scripts/send_chat.py "restart in 5 minutes"                 # everyone
    python3 -I scripts/send_chat.py --to w3 "the human is at the base"      # only w3's chat footer; humans see it in game
    python3 -I scripts/send_chat.py --from stevenli --to all "hello"

RCON settings come from FACTORIO_RCON_HOST / _PORT / _PASSWORD (see rcon.py). The text is data for the agents, not an
instruction channel for the game: use it for run-level notices, not game plans.
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rcon  # noqa: E402

log = logging.getLogger("send_chat")


def build_command(text: str, to: str | None = None, sender: str = "supervisor") -> str:
    """The RCON command for one post_chat call (same string escaping as factorio_mcp.bridge.escape_lua_string)."""
    body = {"text": text, "from": sender}
    if to:
        body["to"] = to
    payload = json.dumps(body, separators=(",", ":")).replace("\\", "\\\\").replace('"', '\\"')
    return f'/silent-command remote.call("factorio_mcp","rpc","post_chat","{payload}")'


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("text")
    ap.add_argument("--to", help="character name (w1..w5) or all; default: everyone")
    ap.add_argument("--from", dest="sender", default="supervisor")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    reply = rcon.command(build_command(args.text, args.to, args.sender))
    log.info("posted to=%s from=%s (%d chars); reply: %s", args.to or "all", args.sender, len(args.text), reply[:200] or "(empty)")
    return 0 if '"ok":true' in reply.replace(" ", "") else 1


if __name__ == "__main__":
    sys.exit(main())
