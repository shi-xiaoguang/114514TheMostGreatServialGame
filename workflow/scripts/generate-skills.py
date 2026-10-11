#!/usr/bin/env python3
"""Generate/check the full local skill index and small Codex/CodeBuddy adapters.

The upstream snapshot is read only. Existing unmanaged or edited adapter files
are never replaced. Run setup-workspace.ps1 to also create native tool links.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys

sys.dont_write_bytecode = True
from skill_catalog import (MANAGER_ID, MANIFEST_NAME, build_index, generated_files, index_bytes)


def is_link(path: Path) -> bool:
    return path.is_symlink() or bool(getattr(path.lstat(), "st_file_attributes", 0) & 0x400)


def current_files(directory: Path) -> dict[str, Path]:
    result = {}
    if not directory.exists():
        return result
    if is_link(directory):
        raise ValueError(f"Adapter directory cannot be a link: {directory}")
    for path, directories, files in os.walk(directory, followlinks=False):
        for name in directories + files:
            target = Path(path) / name
            if is_link(target):
                raise ValueError(f"Unexpected link in generated adapters: {target}")
        for name in files:
            target = Path(path) / name
            if target != directory / MANIFEST_NAME:
                result[target.relative_to(directory).as_posix()] = target
    return result


def manifest_bytes(files: dict[str, bytes]) -> bytes:
    manifest = {"manager": MANAGER_ID, "files": {
        name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())}}
    return (json.dumps(manifest, indent=2) + "\n").encode("utf-8")


def ensure_managed(directory: Path, current: dict[str, Path]) -> None:
    marker = directory / MANIFEST_NAME
    if not marker.exists():
        if current or (directory.exists() and any(directory.iterdir())):
            raise ValueError(f"Refusing to replace unmanaged adapter directory: {directory}")
        return
    if is_link(marker):
        raise ValueError("Adapter management manifest cannot be a link")
    marker_data = json.loads(marker.read_text(encoding="utf-8"))
    if marker_data.get("manager") != MANAGER_ID or not isinstance(marker_data.get("files"), dict):
        raise ValueError("Unrecognized adapter management manifest")
    managed = marker_data["files"]
    for name in managed:
        relative = PurePosixPath(name)
        if ("\\" in name or ":" in name or relative.is_absolute() or ".." in relative.parts
                or relative.as_posix() != name):
            raise ValueError(f"Invalid managed adapter path: {name!r}")
    for name, path in current.items():
        if name not in managed:
            raise ValueError(f"Refusing to replace unmanaged adapter file: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != managed[name]:
            raise ValueError(f"Adapter was edited; preserve/review before regeneration: {name}")


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp-robinson")
    if temporary.exists():
        raise ValueError(f"Temporary output already exists; inspect before retrying: {temporary}")
    created = False
    try:
        with temporary.open("xb") as stream:
            created = True
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if created and temporary.exists():
            temporary.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--check", action="store_true", help="Compare expected files without writing")
    args = parser.parse_args()
    root = args.root.resolve()
    directory = root / "workflow/skills"
    try:
        # Refuse writes through redirected parents or outside this checkout.
        if not directory.resolve().is_relative_to(root) or is_link(root / "workflow"):
            raise ValueError("Adapter output must stay inside this checkout")
        index = build_index(root)
        desired = generated_files(index)
        current = current_files(directory)
        expected_outputs = {directory / name: data for name, data in desired.items()}
        expected_outputs[directory / MANIFEST_NAME] = manifest_bytes(desired)
        expected_outputs[root / "workflow/skills-index.json"] = index_bytes(index)
        stale = sorted(current.keys() - desired.keys())
        changed = [path for path, data in expected_outputs.items()
                   if not path.is_file() or path.read_bytes() != data]
        if args.check:
            if stale or changed:
                for path in changed:
                    print(f"Missing/outdated generated file: {path.relative_to(root).as_posix()}")
                for name in stale:
                    print(f"Unexpected generated adapter: {name}")
                return 1
            print(f"Skill index and {len(desired)} adapters are current.")
            return 0
        ensure_managed(directory, current)
        for path in expected_outputs:
            if path.exists() and is_link(path):
                raise ValueError(f"Output cannot be a link: {path}")
        for path in changed:
            atomic_write(path, expected_outputs[path])
        for name in stale:
            path = current[name]
            if not path.resolve().is_relative_to(directory.resolve()):
                raise ValueError(f"Stale adapter escaped output directory: {name}")
            path.unlink()
            if path.parent != directory and not any(path.parent.iterdir()):
                path.parent.rmdir()
        print(f"Generated {len(desired)} adapters; updated {len(changed)} files; removed {len(stale)} stale managed files.")
        return 0
    except (OSError, UnicodeError, ValueError, KeyError, TypeError) as exc:
        print(f"Skill generation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
