#!/usr/bin/env python3
"""Build and verify a deterministic, single-root Roth Chat install ZIP."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import sys
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

import project

ADDON_ROOT = PurePosixPath("RothChat")
FIXED_TIME = (1980, 1, 1, 0, 0, 0)
RELEASE_FILES = (
    Path("LICENSE.md"),
    Path("README.md"),
    Path("CHANGELOG.md"),
    Path("ThirdParty/ATTRIBUTIONS.md"),
    Path("ThirdParty/GLASS_LICENSE.txt"),
    Path("ThirdParty/LS_GLASS_LICENSE.txt"),
)
SERVICE_PARTS = {
    ".git", ".github", "scripts", "tests", "dist", "__pycache__",
    "AGENT_GUIDE.md", "ARCHITECTURE.md", "CODE_INDEX.md", "TODO.md",
}
ASSET_REFERENCE = re.compile(r"RothChat(?:\\\\|/)+Assets(?:\\\\|/)+([^\"'\n]+)")


class PackageError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_source(relative: Path) -> Path:
    source = (project.ROOT / relative).resolve()
    try:
        source.relative_to(project.ROOT)
    except ValueError as exc:
        raise PackageError(f"package path escapes project root: {relative}") from exc
    if not source.is_file() or source.is_symlink():
        raise PackageError(f"missing or unsafe package file: {relative}")
    return source


def _asset_files() -> list[Path]:
    assets = project.ROOT / "Assets"
    if not assets.is_dir():
        raise PackageError("missing Assets directory")
    files = sorted(path for path in assets.rglob("*") if path.is_file())
    if not files:
        raise PackageError("Assets directory is empty")
    for path in files:
        if path.is_symlink():
            raise PackageError(f"symlinked asset is not allowed: {path.relative_to(project.ROOT)}")
    return [path.relative_to(project.ROOT) for path in files]


def _validate_asset_references(loaded: list[Path], assets: list[Path]) -> None:
    available = {
        relative.relative_to("Assets").as_posix().casefold(): relative
        for relative in assets
    }
    for source in loaded:
        if source.suffix.lower() != ".lua":
            continue
        text = source.read_text(encoding="utf-8-sig")
        for match in ASSET_REFERENCE.finditer(text):
            name = match.group(1).replace("\\\\", "/").replace("\\", "/")
            key = name.casefold()
            candidates = [key]
            if not PurePosixPath(name).suffix:
                candidates.extend((key + ".tga", key + ".blp"))
            if not any(candidate in available for candidate in candidates):
                raise PackageError(
                    f"missing referenced asset {name!r} from {source.relative_to(project.ROOT)}"
                )


def collect_files() -> dict[PurePosixPath, Path]:
    """Return the exact allowlisted archive map."""
    _, loaded = project.load_project()
    relative_paths = [Path("RothChat.toc")]
    relative_paths.extend(path.relative_to(project.ROOT) for path in loaded)
    assets = _asset_files()
    relative_paths.extend(assets)
    relative_paths.extend(RELEASE_FILES)
    _validate_asset_references(loaded, assets)

    files: dict[PurePosixPath, Path] = {}
    for relative in relative_paths:
        source = _safe_source(relative)
        archive_path = ADDON_ROOT / PurePosixPath(relative.as_posix())
        if archive_path in files:
            raise PackageError(f"duplicate package path: {archive_path}")
        files[archive_path] = source
    return files


def _zip_info(name: str) -> ZipInfo:
    info = ZipInfo(name, FIXED_TIME)
    info.compress_type = ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    return info


def verify(path: Path) -> tuple[str, int]:
    if not path.is_file():
        raise PackageError(f"archive does not exist: {path}")
    expected = collect_files()
    expected_names = [str(name) for name in sorted(expected, key=str)]

    with ZipFile(path) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if names != sorted(names):
            raise PackageError("ZIP entries are not sorted")
        if len(names) != len(set(names)):
            raise PackageError("duplicate ZIP entries")
        if names != expected_names:
            missing = sorted(set(expected_names) - set(names))
            extra = sorted(set(names) - set(expected_names))
            raise PackageError(f"package mismatch: missing={missing[:8]} extra={extra[:8]}")

        for info in infos:
            member = PurePosixPath(info.filename)
            if member.is_absolute() or not member.parts or member.parts[0] != str(ADDON_ROOT):
                raise PackageError(f"unexpected archive root: {info.filename}")
            if any(part in {"", ".", ".."} or part in SERVICE_PARTS for part in member.parts):
                raise PackageError(f"unsafe or service path in package: {info.filename}")
            if info.is_dir():
                raise PackageError(f"unexpected directory entry: {info.filename}")
            if info.date_time != FIXED_TIME:
                raise PackageError(f"non-deterministic timestamp: {info.filename}")
            source = expected[member]
            if archive.read(info) != source.read_bytes():
                raise PackageError(f"archive bytes differ from source: {info.filename}")

        bad = archive.testzip()
        if bad:
            raise PackageError(f"corrupt ZIP member: {bad}")

    return sha256(path), len(expected_names)


def build(output: Path) -> tuple[str, int]:
    files = collect_files()
    output = output.resolve()
    if output.suffix.lower() != ".zip":
        raise PackageError("output must use the .zip extension")
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for archive_path in sorted(files, key=str):
            archive.writestr(_zip_info(str(archive_path)), files[archive_path].read_bytes(), compresslevel=9)
    return verify(output)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        help="ZIP path; default: dist/RothChat-<TOC version>.zip",
    )
    parser.add_argument("--verify", action="store_true", help="verify an existing ZIP without rebuilding it")
    args = parser.parse_args(argv)

    try:
        metadata, _ = project.load_project()
        output = args.output or project.ROOT / "dist" / f"RothChat-{metadata['Version']}.zip"
        if not output.is_absolute():
            output = Path.cwd() / output
        digest, count = verify(output) if args.verify else build(output)
    except (OSError, ValueError, PackageError) as exc:
        print(f"package: ERROR: {exc}", file=sys.stderr)
        return 1

    action = "verified" if args.verify else "built"
    print(f"{action} {output}: {count} files, sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
