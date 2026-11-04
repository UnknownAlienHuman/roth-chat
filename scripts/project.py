#!/usr/bin/env python3
"""Shared Roth Chat project graph and metadata contracts."""
from __future__ import annotations

from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "RothChat.toc"
EXPECTED_INTERFACE = "120105"
EXPECTED_AUTHOR = "Neomorph"
EXPECTED_SAVED_VARIABLES = "RothChatDB"
VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+(?:[-.][A-Za-z0-9]+)*")


def _inside_root(path: Path) -> bool:
    try:
        path.relative_to(ROOT)
        return True
    except ValueError:
        return False


def load_project() -> tuple[dict[str, str], list[Path]]:
    """Return validated TOC metadata and the exact recursive load graph."""
    metadata: dict[str, str] = {}
    loaded: list[Path] = []
    seen: set[Path] = set()

    def visit(relative: Path) -> None:
        path = (ROOT / relative).resolve()
        if not _inside_root(path) or not path.is_file():
            raise ValueError(f"Missing or invalid load path: {relative}")
        if path in seen:
            raise ValueError(f"Duplicate load path: {relative}")
        seen.add(path)
        loaded.append(path)
        if path.suffix.lower() != ".xml":
            return
        try:
            document = ET.parse(path)
        except ET.ParseError as exc:
            raise ValueError(f"Malformed XML load file: {path.relative_to(ROOT)}: {exc}") from exc
        for node in document.iter():
            child = node.attrib.get("file")
            if not child:
                continue
            child_path = (path.parent / child.replace("\\", "/")).resolve()
            if not _inside_root(child_path):
                raise ValueError(f"XML load path escapes project root: {child}")
            visit(child_path.relative_to(ROOT))

    if not TOC.is_file():
        raise ValueError("Missing RothChat.toc")
    for raw in TOC.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if line.startswith("##") and ":" in line:
            key, value = line[2:].split(":", 1)
            metadata[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            visit(Path(line.replace("\\", "/")))

    for key in ("Interface", "Version", "Author", "SavedVariables"):
        if not metadata.get(key):
            raise ValueError(f"Missing TOC metadata: {key}")
    if metadata["Interface"] != EXPECTED_INTERFACE:
        raise ValueError(f"Unexpected Retail interface: {metadata['Interface']}")
    if metadata["Author"] != EXPECTED_AUTHOR:
        raise ValueError(f"Unexpected addon author: {metadata['Author']}")
    if metadata["SavedVariables"] != EXPECTED_SAVED_VARIABLES:
        raise ValueError("SavedVariables identity changed")
    if not VERSION_PATTERN.fullmatch(metadata["Version"]):
        raise ValueError("Invalid addon version")

    return metadata, loaded


def loaded_relative_paths() -> list[Path]:
    return [path.relative_to(ROOT) for path in load_project()[1]]
