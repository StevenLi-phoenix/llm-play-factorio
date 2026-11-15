#!/usr/bin/env python3
"""Pack a Factorio mod folder into the zip a client installs: <name>_<version>.zip with the single top-level folder
<name>_<version>/ (Factorio's layout). name and version come from the folder's info.json.

  python3 scripts/pack_mod.py factorio-mcp/mod/factorio-mcp /path/to/out_dir     # prints the zip path

Clients joining a server need every mod in the server's mod-list.json at the same version; the zip goes into the
client's mods folder (Windows %APPDATA%\\Factorio\\mods).
"""
from __future__ import annotations

import json
import logging
import sys
import zipfile
from pathlib import Path

log = logging.getLogger("pack_mod")
SKIP_DIRS = {"__pycache__", ".git"}


def pack(mod_dir: Path, out_dir: Path) -> Path:
    info = json.loads((mod_dir / "info.json").read_text(encoding="utf-8"))
    name, version = str(info["name"]), str(info["version"])
    top = f"{name}_{version}"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{top}.zip"
    files = sorted(p for p in mod_dir.rglob("*")
                   if p.is_file() and not (SKIP_DIRS & set(p.relative_to(mod_dir).parts)) and not p.name.startswith("."))
    tmp = out.with_name(out.name + ".part")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p, f"{top}/{p.relative_to(mod_dir).as_posix()}")
    tmp.replace(out)
    log.info("packed %d files into %s (%d bytes)", len(files), out, out.stat().st_size)
    return out


def main(argv: list[str]) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", stream=sys.stderr)
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    print(pack(Path(argv[0]), Path(argv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
