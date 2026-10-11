#!/usr/bin/env python3
"""Replay the 20 integration-tool checks using disposable in-repository fixtures."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parents[1]
spec = importlib.util.spec_from_file_location("workspace_validator", SCRIPTS / "validate-workspace.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def state(root: Path) -> dict[str, str]:
    return {path.relative_to(root).as_posix(): digest(path)
            for path in root.rglob("*") if path.is_file()}


def generate(root: Path, *arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-B", str(SCRIPTS / "generate-skills.py"),
                           "--root", str(root), *arguments],
                          capture_output=True, text=True, timeout=30)


def check_snapshot_and_resources(root: Path, cases: list[str]) -> None:
    vendor = root / validator.UPSTREAM_RELATIVE
    vendor.mkdir(parents=True)
    source = vendor / "README.md"
    source.write_bytes(b"original\r\n")
    manifest = {"repository": validator.UPSTREAM_REPOSITORY, "commit": "a" * 40,
                "file_count": 1, "skill_count": 189,
                "files": [{"path": "README.md", "sha256": digest(source)}]}
    lock = root / "workflow/upstream-lock.json"
    lock.write_text(json.dumps(manifest), encoding="utf-8")

    def snapshot_fails() -> bool:
        report = validator.Report(root)
        validator.check_upstream(report)
        return report.checks[0]["status"] == "fail"

    assert not snapshot_fails()
    cases.append("valid byte snapshot")
    source.write_bytes(b"original\n")
    assert snapshot_fails()
    cases.append("CRLF-to-LF tampering detected")
    source.write_bytes(b"original\r\n")
    extra = vendor / "extra.txt"
    extra.write_text("extra", encoding="utf-8")
    assert snapshot_fails()
    cases.append("extra upstream file detected")
    extra.unlink()
    nested = vendor / ".git"
    nested.mkdir()
    assert snapshot_fails()
    cases.append("nested Git detected")
    nested.rmdir()
    manifest["files"][0]["path"] = "../escape"
    lock.write_text(json.dumps(manifest), encoding="utf-8")
    assert snapshot_fails()
    cases.append("manifest path traversal rejected")

    game = root / "game"
    game.mkdir()
    gd = game / "check.gd"
    (game / "present.tres").write_text("", encoding="utf-8")
    gd.write_text('var ok = load("res://present.tres")\n'
                  'var dynamic = load("res://%s.tres" % x)\n', encoding="utf-8")
    report = validator.Report(root)
    validator.check_resources(report)
    assert report.checks[0]["status"] == "pass"
    assert len(report.checks[0]["dynamic_literals_not_checked"]) == 1
    cases.append("valid literals pass and dynamic literals disclosed")
    gd.write_text('var bad = load("res://missing.tres")\n', encoding="utf-8")
    report = validator.Report(root)
    validator.check_resources(report)
    assert report.checks[0]["status"] == "fail"
    cases.append("missing resource detected")
    gd.write_text('var bad = load("res://../workflow/README.md")\n', encoding="utf-8")
    report = validator.Report(root)
    validator.check_resources(report)
    assert report.checks[0]["status"] == "fail"
    cases.append("escaping resource rejected")
    report = validator.Report(root)
    validator.check_native_links(report, [], False)
    assert report.checks[0]["status"] == "pass" and len(report.checks[0]["warnings"]) == 2
    report = validator.Report(root)
    validator.check_native_links(report, [], True)
    assert report.checks[0]["status"] == "fail"
    cases.append("optional/required missing links distinguished")


def check_generator(root: Path, cases: list[str]) -> None:
    skills = root / validator.UPSTREAM_RELATIVE / "skills"
    for i in range(189):
        name = "skill-" + str(i)
        directory = skills / name
        directory.mkdir(parents=True)
        (directory / "SKILL.md").write_text(
            '---\nname: ' + name + '\ndescription: "Fixture description"\n---\nBody\n',
            encoding="utf-8")
    (root / "workflow/upstream-lock.json").write_text(json.dumps({"commit": "a" * 40}), encoding="utf-8")
    result = generate(root)
    assert result.returncode == 0, result.stderr
    cases.append("generate all 189 routes")
    baseline = state(root)
    assert generate(root, "--check").returncode == 0 and state(root) == baseline
    cases.append("check is read-only")
    assert generate(root).returncode == 0 and state(root) == baseline
    cases.append("regeneration is deterministic/idempotent")
    adapter = root / "workflow/skills/skill-0/SKILL.md"
    original = adapter.read_bytes()
    adapter.write_text("user edit", encoding="utf-8")
    edited = state(root)
    assert generate(root).returncode == 1 and state(root) == edited
    cases.append("user adapter edit blocks writes and is preserved")
    assert generate(root, "--check").returncode == 1 and state(root) == edited
    cases.append("check detects changed adapter without writing")
    adapter.write_bytes(original)
    custom = root / "workflow/skills/custom.txt"
    custom.write_text("user data", encoding="utf-8")
    baseline = state(root)
    assert generate(root).returncode == 1 and state(root) == baseline
    cases.append("unmanaged file blocks writes and is preserved")
    custom.unlink()
    (skills / "skill-0").rename(skills / "skill-renamed")
    source = skills / "skill-renamed/SKILL.md"
    source.write_text(source.read_text(encoding="utf-8").replace("name: skill-0", "name: skill-renamed"),
                      encoding="utf-8")
    result = generate(root)
    assert result.returncode == 0, result.stderr
    assert not adapter.exists() and (root / "workflow/skills/skill-renamed/SKILL.md").is_file()
    assert generate(root, "--check").returncode == 0
    cases.append("stale managed adapter safely replaced after source rename")


def check_catalog_and_evidence(root: Path, cases: list[str]) -> None:
    original = ROOT / validator.UPSTREAM_RELATIVE
    destination = root / validator.UPSTREAM_RELATIVE
    for directory in (original / "skills").iterdir():
        if directory.is_dir():
            target = destination / "skills" / directory.name
            target.mkdir(parents=True)
            shutil.copyfile(directory / "SKILL.md", target / "SKILL.md")
    shutil.copyfile(original / "skills_index.json", destination / "skills_index.json")
    (root / "workflow/upstream-lock.json").write_text(json.dumps({"commit": "a" * 40}), encoding="utf-8")
    result = generate(root)
    assert result.returncode == 0, result.stderr
    report = validator.Report(root)
    names = validator.check_skills(report)
    assert report.checks[0]["status"] == "pass" and len(names) == 189
    assert len(report.checks[0]["warnings"]) == 3
    cases.append("upstream defects disclosed while full canonical routes pass")
    adapted = root / "workflow/skills/godot-ai-navigation/SKILL.md"
    adapted.write_text(adapted.read_text(encoding="utf-8").replace(
        "name: godot-ai-navigation", "name: godot-navigation-pathfinding"), encoding="utf-8")
    report = validator.Report(root)
    validator.check_skills(report)
    assert report.checks[0]["status"] == "fail"
    cases.append("adapter name collision rejected")
    index = root / "workflow/skills-index.json"
    content = json.loads(index.read_text(encoding="utf-8"))
    content["skills"].pop()
    index.write_text(json.dumps(content), encoding="utf-8")
    report = validator.Report(root)
    validator.check_skills(report)
    assert any("skills-index" in error for error in report.checks[0]["errors"])
    cases.append("local index missing skill rejected")
    before = digest(index)
    # Deliberately invalid fixture: this exercises output refusal, not another
    # validation run against the real checkout or native application links.
    result = subprocess.run([sys.executable, "-B", str(SCRIPTS / "validate-workspace.py"),
                             "--root", str(root), "--output", str(index)],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 2 and "Evidence output already exists" in result.stdout
    assert "Traceback" not in result.stdout + result.stderr and digest(index) == before
    cases.append("existing evidence refused with exit 2 and original bytes preserved")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Save JSON evidence; existing files are never overwritten")
    args = parser.parse_args()
    if not __debug__:
        parser.error("Run without -O; assertions must stay enabled")
    if args.output and args.output.exists():
        parser.error("Evidence file already exists; choose a new output path")
    scratch_parent = ROOT / "game/.godot"
    if not scratch_parent.resolve().is_relative_to(ROOT):
        parser.error("Fixture directory must resolve inside this checkout")
    scratch_parent.mkdir(parents=True, exist_ok=True)
    cases = []
    failure = None
    try:
        with tempfile.TemporaryDirectory(prefix="skill-tools-selftest-", dir=scratch_parent) as temporary:
            scratch = Path(temporary)
            check_snapshot_and_resources(scratch / "snapshot", cases)
            check_generator(scratch / "generator", cases)
            check_catalog_and_evidence(scratch / "catalog", cases)
        assert len(cases) == 20
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as exc:
        failure = f"{type(exc).__name__}: {exc}"
    evidence = {"timestamp_utc": datetime.now(timezone.utc).isoformat(),
                "status": "fail" if failure else "pass", "passed": len(cases), "expected": 20,
                "cases": cases, "failure": failure,
                "scope": "Disposable fixtures inside game/.godot; real source files read only",
                "script_sha256": {name: digest(SCRIPTS / name) for name in
                    ("test-skill-tools.py", "generate-skills.py", "skill_catalog.py", "validate-workspace.py")}}
    serialized = json.dumps(evidence, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(serialized)
    print(serialized, end="")
    return 1 if failure else 0


if __name__ == "__main__":
    sys.exit(main())
