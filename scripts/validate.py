#!/usr/bin/env python3
"""Validate load ownership, metadata, Lua syntax and all contract specs."""
from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def load_paths():
    metadata, loaded = {}, []

    def visit(relative):
        path = (ROOT / relative).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise ValueError(f"Missing or invalid load path: {relative}")
        if path in loaded:
            raise ValueError(f"Duplicate load path: {relative}")
        loaded.append(path)
        if path.suffix.lower() == ".xml":
            for node in ET.parse(path).iter():
                child = node.attrib.get("file")
                if child:
                    visit((path.parent / child.replace("\\", "/")).relative_to(ROOT))

    for raw in (ROOT / "RothChat.toc").read_text().splitlines():
        line = raw.strip()
        if line.startswith("##") and ":" in line:
            key, value = line[2:].split(":", 1)
            metadata[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            visit(Path(line.replace("\\", "/")))
    for key in ("Interface", "Version", "Author", "SavedVariables"):
        if not metadata.get(key):
            raise ValueError(f"Missing TOC metadata: {key}")
    if metadata["Interface"] != "120105" or metadata["Author"] != "Neomorph":
        raise ValueError("Unexpected Retail interface or author")
    if metadata["SavedVariables"] != "RothChatDB":
        raise ValueError("SavedVariables identity changed")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-.][A-Za-z0-9]+)*", metadata["Version"]):
        raise ValueError("Invalid addon version")

    owned = set(ROOT.glob("*.lua")) | set((ROOT / "Modules").glob("*.lua"))
    unloaded = owned - set(loaded)
    if unloaded:
        raise ValueError("Unloaded first-party code: " + ", ".join(str(p.relative_to(ROOT)) for p in sorted(unloaded)))
    definitions = defaultdict(list)
    for path in owned:
        for owner, method in re.findall(r"^function\s+(NS|RothChat|core)[.:](\w+)\s*\(", path.read_text(), re.MULTILINE):
            definitions[("NS" if owner == "NS" else "core", method)].append(path.name)
    duplicates = {name: paths for name, paths in definitions.items() if len(paths) > 1}
    if duplicates:
        raise ValueError(f"Duplicate shared implementation owners: {duplicates}")
    return metadata, loaded


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def invoke(command, source):
    result = subprocess.run(command + ["-e", source], cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).strip() or f"Exit {result.returncode}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", action="append", help="Runtime command; repeat for multiple Lua versions")
    args = parser.parse_args()
    metadata, loaded = load_paths()
    print(f"Roth Chat {metadata['Version']}: Interface {metadata['Interface']}, {len(loaded)} load entries, unique shared owners")
    commands = args.lua or [name for name in ("lua5.1", "lua5.4") if shutil.which(name)]
    if not commands:
        raise ValueError("No Lua runtime found. Install Lua 5.1/5.4 or pass --lua <command>.")
    lua_files = sorted(path.relative_to(ROOT).as_posix() for path in ROOT.rglob("*.lua") if ".git" not in path.parts)
    specs = sorted(path.relative_to(ROOT).as_posix() for path in (ROOT / "tests").glob("*_spec.lua"))
    if not specs:
        raise ValueError("No contract specs discovered")
    for value in commands:
        command = shlex.split(value)
        for path in lua_files:
            invoke(command, f"assert(loadfile({lua_string(path)}))")
        for path in specs:
            invoke(command, f"unpack = unpack or table.unpack; table.unpack = table.unpack or unpack; assert(loadfile({lua_string(path)}))()")
        print(f"{value}: {len(lua_files)} Lua files parsed; {len(specs)} contract specs passed")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError) as exc:
        print(f"Validation failed: {exc}", file=sys.stderr)
        sys.exit(1)
