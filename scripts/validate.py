#!/usr/bin/env python3
"""Validate load ownership, Lua syntax and all contract specs."""
from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

import project

ROOT = project.ROOT


def validate_ownership(loaded: list[Path]) -> None:
    owned = set(ROOT.glob("*.lua")) | set((ROOT / "Modules").glob("*.lua"))
    unloaded = owned - set(loaded)
    if unloaded:
        raise ValueError(
            "Unloaded first-party code: "
            + ", ".join(str(path.relative_to(ROOT)) for path in sorted(unloaded))
        )

    definitions: dict[tuple[str, str], list[str]] = defaultdict(list)
    for path in owned:
        text = path.read_text(encoding="utf-8-sig")
        for owner, method in re.findall(r"^function\s+(NS|RothChat|core)[.:](\w+)\s*\(", text, re.MULTILINE):
            definitions[("NS" if owner == "NS" else "core", method)].append(path.name)
    duplicates = {name: paths for name, paths in definitions.items() if len(paths) > 1}
    if duplicates:
        raise ValueError(f"Duplicate shared implementation owners: {duplicates}")


def lua_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def invoke(command: list[str], source: str) -> None:
    result = subprocess.run(command + ["-e", source], cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).strip() or f"Exit {result.returncode}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", action="append", help="Runtime command; repeat for multiple Lua versions")
    args = parser.parse_args()

    metadata, loaded = project.load_project()
    validate_ownership(loaded)
    print(
        f"Roth Chat {metadata['Version']}: Interface {metadata['Interface']}, "
        f"{len(loaded)} load entries, unique shared owners"
    )

    commands = args.lua or [name for name in ("lua5.1", "lua5.4") if shutil.which(name)]
    if not commands:
        raise ValueError("No Lua runtime found. Install Lua 5.1/5.4 or pass --lua <command>.")

    lua_files = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.lua")
        if ".git" not in path.parts
    )
    specs = sorted(path.relative_to(ROOT).as_posix() for path in (ROOT / "tests").glob("*_spec.lua"))
    if not specs:
        raise ValueError("No contract specs discovered")

    for value in commands:
        command = shlex.split(value)
        for path in lua_files:
            invoke(command, f"assert(loadfile({lua_string(path)}))")
        for path in specs:
            invoke(
                command,
                "unpack = unpack or table.unpack; table.unpack = table.unpack or unpack; "
                f"assert(loadfile({lua_string(path)}))()",
            )
        print(f"{value}: {len(lua_files)} Lua files parsed; {len(specs)} contract specs passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError) as exc:
        print(f"Validation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
