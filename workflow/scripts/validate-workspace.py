#!/usr/bin/env python3
"""Check the Robinson checkout without importing Godot or third-party packages.

This is a static integration check, not a substitute for Godot import/runtime
tests. Resource checks cover quoted, complete res:// literals; dynamic paths,
uid:// references and the correctness of upstream examples require other checks.
The lock is a local integrity manifest, not a cryptographic upstream signature.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from skill_catalog import (EXPECTED_SKILLS, MANAGER_ID, MANIFEST_NAME, build_index,
                           frontmatter, generated_files)


UPSTREAM_REPOSITORY = "https://github.com/bgrenat/godot-game-dev-studio"
UPSTREAM_RELATIVE = Path("workflow/vendor/godot-game-dev-studio")
GAME_TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".godot", ".gdshader", ".gdshaderinc", ".cfg"}
RESOURCE_LITERAL = re.compile(r'''["']\*?(res://[^"'\r\n]*)["']''')
SKIP_GENERATED = {".godot", "__pycache__"}


class Report:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.checks: list[dict] = []
        self.facts: dict = {}

    def record(self, name: str, errors: list[str], **details: object) -> None:
        self.checks.append({"name": name, "status": "fail" if errors else "pass",
                            "errors": errors, **details})


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def is_link(path: Path) -> bool:
    # Windows junctions are reparse points, but are not is_symlink() on Python 3.11.
    return path.is_symlink() or bool(getattr(path.lstat(), "st_file_attributes", 0) & 0x400)


def walk_files(root: Path, skip: set[str] | None = None) -> tuple[list[Path], list[str]]:
    files: list[Path] = []
    errors: list[str] = []
    if not root.is_dir():
        return files, [f"Missing directory: {root}"]
    if is_link(root):
        return files, [f"Unexpected linked source directory: {root}"]
    for directory, directories, names in os.walk(root, followlinks=False):
        current = Path(directory)
        for name in directories[:]:
            path = current / name
            if name in (skip or set()):
                directories.remove(name)
            elif name == ".git" or is_link(path):
                errors.append(f"Unexpected repository/link: {path.relative_to(root).as_posix()}")
                directories.remove(name)
        for name in names:
            path = current / name
            if name == ".git" or is_link(path):
                errors.append(f"Unexpected repository/link: {path.relative_to(root).as_posix()}")
            else:
                files.append(path)
    return sorted(files), errors


def check_layout(report: Report) -> None:
    root = report.root
    errors = []
    for relative in ("game/project.godot", "workflow/README.md", "workflow/upstream-lock.json",
                     "workflow/scripts/run-tests.ps1", "AGENTS.md", "CODEBUDDY.md",
                     "AI_TEAM_RULES.md", "PROJECT_STATUS.md", "README.md", "Robinson.code-workspace"):
        if not (root / relative).is_file():
            errors.append(f"Missing file: {relative}")
    for relative in ("project.godot", "scripts", "scenes", "resources", "tests", "tools/run-tests.ps1"):
        if (root / relative).exists():
            errors.append(f"Obsolete game/test entry at repository root: {relative}")
    for relative in ("game/workflow", "game/vendor", "game/.agents", "game/.codebuddy"):
        if (root / relative).exists():
            errors.append(f"Workflow must stay outside the game: {relative}")
    report.record("layout", errors, godot_project="game/project.godot")


def check_upstream(report: Report) -> dict:
    root = report.root
    vendor = root / UPSTREAM_RELATIVE
    lock = json.loads(read_text(root / "workflow/upstream-lock.json"))
    if not isinstance(lock, dict):
        raise ValueError("upstream-lock.json must contain an object")
    errors = []
    if lock.get("repository") != UPSTREAM_REPOSITORY:
        errors.append("Unexpected upstream repository")
    if not re.fullmatch(r"[0-9a-f]{40}", str(lock.get("commit", ""))):
        errors.append("Upstream commit must be a full 40-character Git SHA")
    entries = lock.get("files")
    if not isinstance(entries, list):
        raise ValueError("upstream-lock.json files must be a list")
    declared: dict[str, str] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            errors.append("Invalid upstream file entry")
            continue
        name, digest = entry.get("path"), entry.get("sha256")
        if (not isinstance(name, str) or not name or "\\" in name or ":" in name
                or PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts
                or PurePosixPath(name).as_posix() != name):
            errors.append(f"Invalid relative upstream path: {name!r}")
            continue
        if name in declared:
            errors.append(f"Duplicate upstream path: {name}")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            errors.append(f"Invalid SHA256 for {name}")
            continue
        declared[name] = digest
    files, tree_errors = walk_files(vendor)
    errors.extend(tree_errors)
    actual = {path.relative_to(vendor).as_posix(): path for path in files}
    for name in sorted(declared.keys() - actual.keys()):
        errors.append(f"Missing upstream file: {name}")
    for name in sorted(actual.keys() - declared.keys()):
        errors.append(f"Extra upstream file: {name}")
    for name in sorted(declared.keys() & actual.keys()):
        if hashlib.sha256(actual[name].read_bytes()).hexdigest() != declared[name]:
            errors.append(f"Upstream bytes changed: {name}")
    if lock.get("file_count") != len(entries) or len(entries) != len(actual):
        errors.append("Upstream file_count, manifest and actual file count differ")
    if lock.get("skill_count") != EXPECTED_SKILLS:
        errors.append(f"Expected {EXPECTED_SKILLS} skills in pinned snapshot")
    report.facts["upstream_commit"] = lock.get("commit")
    report.record("upstream_snapshot", errors, repository=lock.get("repository"),
                  commit=lock.get("commit"), manifest_files=len(entries), actual_files=len(actual))
    return lock


def check_skills(report: Report) -> list[str]:
    vendor = report.root / UPSTREAM_RELATIVE
    upstream = json.loads(read_text(vendor / "skills_index.json"))
    if not isinstance(upstream, list):
        raise ValueError("skills_index.json must contain a list")
    errors = []
    warnings = []
    upstream_names = []
    for entry in upstream:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            warnings.append("Upstream skill index contains an invalid entry")
            continue
        upstream_names.append(entry["name"])
    for name, count in Counter(upstream_names).items():
        if count > 1:
            warnings.append(f"Preserved upstream duplicate name: {name} ({count} entries)")
    expected = build_index(report.root)
    names = [entry["name"] for entry in expected["skills"]]
    missing = sorted(set(names) - set(upstream_names))
    if missing:
        warnings.append(f"Upstream index omits {len(missing)} skill directories; local index covers all {EXPECTED_SKILLS}")
    renamed = [entry["id"] for entry in expected["skills"] if entry["id"] != entry["declared_name"]]
    for name in renamed:
        warnings.append(f"Upstream frontmatter collision corrected in local adapter: {name}")
    local_index = json.loads(read_text(report.root / "workflow/skills-index.json"))
    if local_index != expected:
        errors.append("Local skills-index.json differs from the complete source-derived catalog; regenerate adapters")
    adapters = report.root / "workflow/skills"
    files, tree_errors = walk_files(adapters)
    errors.extend(tree_errors)
    actual_files = {path.relative_to(adapters).as_posix(): path for path in files}
    desired = generated_files(expected)
    for name in sorted(desired.keys() - actual_files.keys()):
        errors.append(f"Missing generated adapter: {name}")
    for name in sorted(actual_files.keys() - desired.keys() - {MANIFEST_NAME}):
        errors.append(f"Unexpected generated adapter file: {name}")
    for name in sorted(desired.keys() & actual_files.keys()):
        if actual_files[name].read_bytes() != desired[name]:
            errors.append(f"Generated adapter differs from unique canonical route: {name}")
        if frontmatter(read_text(actual_files[name])).get("name") != PurePosixPath(name).parts[0]:
            errors.append(f"Adapter frontmatter name differs from directory: {name}")
    manifest = json.loads(read_text(adapters / MANIFEST_NAME))
    expected_hashes = {name: hashlib.sha256(data).hexdigest() for name, data in desired.items()}
    if manifest.get("manager") != MANAGER_ID or manifest.get("files") != expected_hashes:
        errors.append("Adapter management manifest differs from expected generated files")
    report.record("skill_catalog", errors, upstream_index_entries=len(upstream),
                  upstream_unique_names=len(set(upstream_names)), local_skills=len(names),
                  upstream_missing_directories=missing, upstream_names_adapted=renamed,
                  warnings=warnings)
    return names


def check_entries(report: Report) -> None:
    requirements = {
        "AGENTS.md": ("CODEBUDDY.md",),
        "CODEBUDDY.md": ("AI_TEAM_RULES.md", "PROJECT_STATUS.md", "workflow/README.md"),
        "README.md": ("game/project.godot", "PROJECT_STATUS.md"),
        "PROJECT_STATUS.md": ("game/", "workflow/"),
        "workflow/README.md": ("vendor/godot-game-dev-studio", "skills-index.json",
                               ".agents/skills", ".codebuddy/skills"),
    }
    errors = []
    for relative, references in requirements.items():
        content = read_text(report.root / relative).replace("\\", "/")
        for reference in references:
            if reference not in content:
                errors.append(f"{relative} must reference {reference}")
    report.record("entry_routes", errors, checked_documents=list(requirements))


def check_resources(report: Report) -> None:
    game = report.root / "game"
    files, errors = walk_files(game, SKIP_GENERATED)
    references = 0
    dynamic_paths = []
    uid_count = 0
    for path in files:
        if path.name == "project.godot" and path.parent != game:
            errors.append(f"Nested game project: {path.relative_to(game).as_posix()}")
        if path.suffix not in GAME_TEXT_SUFFIXES:
            continue
        content = read_text(path)
        for line_no, line in enumerate(content.splitlines(), start=1):
            if line.lstrip().startswith(("#", ";")):
                continue
            uid_count += len(re.findall(r'''["']uid://[^"']+["']''', line))
            for match in RESOURCE_LITERAL.finditer(line):
                value = match.group(1)[6:]
                location = f"game/{path.relative_to(game).as_posix()}:{line_no}"
                if re.search(r"[%{}]", value) or re.match(r"\s*\+", line[match.end():]):
                    dynamic_paths.append(location)
                    continue
                references += 1
                relative = PurePosixPath(value)
                if "\\" in value or ":" in value or relative.is_absolute() or ".." in relative.parts:
                    errors.append(f"Resource escapes/invalidates game boundary: {location}: res://{value}")
                    continue
                target = game / relative
                if not target.resolve().is_relative_to(game.resolve()):
                    errors.append(f"Resource resolves outside game: {location}: res://{value}")
                elif not target.exists():
                    errors.append(f"Missing resource: {location}: res://{value}")
                elif relative.parts and relative.parts[0] in {"workflow", "vendor", ".agents", ".codebuddy"}:
                    errors.append(f"Game depends on workflow files: {location}: res://{value}")
    report.record("game_resources", errors, game_files=len(files), literal_references=references,
                  dynamic_literals_not_checked=dynamic_paths, uid_literals_not_checked=uid_count)


def check_native_links(report: Report, names: list[str], required: bool) -> None:
    target = (report.root / "workflow/skills").resolve()
    errors = []
    warnings = []
    checked_files = 0
    for relative in (".agents/skills", ".codebuddy/skills"):
        entry = report.root / relative
        if not entry.exists():
            (errors if required else warnings).append(f"Native skill route absent: {relative}; run setup-workspace.ps1")
            continue
        if not is_link(entry) or entry.resolve() != target:
            errors.append(f"Native skill route must link to workflow/skills: {relative}")
            continue
        for name in names:
            routed = entry / name / "SKILL.md"
            checked_files += 1
            if not routed.is_file() or routed.resolve() != target / name / "SKILL.md":
                errors.append(f"Broken native skill route: {relative}/{name}/SKILL.md")
            source_relative = UPSTREAM_RELATIVE / "skills" / name / "SKILL.md"
            routed_source = routed.parent / "../../.." / source_relative
            if not routed_source.is_file() or routed_source.resolve() != report.root / source_relative:
                errors.append(f"Broken native route to upstream source: {relative}/{name}")
    report.record("native_skill_routes", errors, required=required, warnings=warnings,
                  routed_files_checked=checked_files)


def git_head(root: Path) -> str | None:
    try:
        result = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                                capture_output=True, text=True, timeout=10, check=False)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2],
                        help="Checkout root (defaults to this script's repository)")
    parser.add_argument("--output", type=Path, help="Write full JSON evidence to this path")
    parser.add_argument("--require-native-links", action="store_true",
                        help="Fail if local Codex/CodeBuddy skill links have not been bootstrapped")
    args = parser.parse_args()
    report = Report(args.root.resolve())
    names = []
    checks = [("layout", check_layout), ("upstream_snapshot", check_upstream),
              ("skill_catalog", check_skills), ("entry_routes", check_entries),
              ("game_resources", check_resources)]
    for name, check in checks:
        try:
            result = check(report)
            if name == "skill_catalog":
                names = result
        except (OSError, UnicodeError, ValueError, TypeError, KeyError) as exc:
            report.record(name, [f"Cannot complete check: {exc}"])
    try:
        check_native_links(report, names, args.require_native_links)
    except (OSError, ValueError) as exc:
        report.record("native_skill_routes", [f"Cannot complete check: {exc}"])
    failed = sum(check["status"] == "fail" for check in report.checks)
    evidence = {
        "schema_version": 1,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "repository_root": str(report.root),
        "git_head": git_head(report.root),
        "scope": "Current working files; static integration checks, not runtime acceptance",
        "limitations": ["Lock hashes validate against the local manifest, not an upstream signature",
                        "Dynamic resource paths and uid:// resolution require Godot validation",
                        "Skill routing does not prove application discovery, invocation or MCP connectivity"],
        "status": "fail" if failed else "pass",
        "facts": report.facts,
        "checks": report.checks,
    }
    for check in report.checks:
        print(f"[{check['status'].upper()}] {check['name']}")
        for error in check["errors"]:
            print(f"  {error}")
        for warning in check.get("warnings", []):
            print(f"  WARNING: {warning}")
    print(f"{len(report.checks) - failed}/{len(report.checks)} check groups passed.")
    if args.output:
        try:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with args.output.open("x", encoding="utf-8", newline="\n") as stream:
                stream.write(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        except FileExistsError:
            print(f"[ERROR] Evidence output already exists; choose a new path: {args.output.resolve()}")
            print("Existing evidence was preserved; current results were not saved.")
            return 2
        except OSError as exc:
            print(f"[ERROR] Cannot write evidence: {exc}")
            return 2
        print(f"Evidence: {args.output.resolve()}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
