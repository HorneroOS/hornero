#!/usr/bin/env python3
"""Cross-gate: the release-candidate manifest pins must equal live main SHAs.

Usage:
    python3 scripts/check-pins.py [--root DIR] [--manifest FILE]

Composition manifests are immutable release records: a new release gets
a new file under ``manifests/`` and historical manifests are never
rewritten. Freshness against live component mains is therefore enforced
only for the ONE release-candidate manifest named by
``manifests/candidate`` (override with ``--manifest``). Every other
manifest still gets structural validation (it must parse and any
``pinned`` entry must carry a well-formed 40-char SHA), but a
historical pin is allowed to remain historical.

Exit 0 when the candidate pins are fresh, 1 otherwise (with bump
instructions).

Network access to github.com is required: a pin cannot be proven
fresh offline.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("ERROR: PyYAML is required (pip install pyyaml)")

SHA_RE = re.compile(r"^[0-9a-f]{40}$")
PINNED_COMPONENTS = ("shell", "config")
CANDIDATE_POINTER = "candidate"


def read_candidate_name(root: Path) -> str:
    """Return the candidate manifest filename from manifests/candidate.

    The pointer is a committed file, so candidate selection is explicit,
    reviewable, and deterministic: CI can never silently check (or bump)
    the wrong manifest.
    """
    pointer = root / "manifests" / CANDIDATE_POINTER
    try:
        name = pointer.read_text(encoding="utf-8").strip().splitlines()
    except OSError as exc:
        raise RuntimeError(f"cannot read {pointer}: {exc}") from exc
    names = [line.strip() for line in name if line.strip() and not line.strip().startswith("#")]
    if len(names) != 1 or "/" in names[0] or not names[0].endswith(".yaml"):
        raise RuntimeError(
            f"{pointer} must name exactly one manifest file "
            f"(e.g. 'v0.2.0-preview2.yaml'), got: {names!r}"
        )
    candidate = root / "manifests" / names[0]
    if not candidate.is_file():
        raise RuntimeError(f"candidate manifest '{names[0]}' does not exist")
    return names[0]


def manifest_pin_entries(manifest_path: Path) -> list[tuple[str, str, str, str, str]]:
    """Return (manifest_file, component, repo, ref, sha) for shell/config pins."""
    with manifest_path.open(encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict):
        return []
    components = doc.get("components")
    if not isinstance(components, dict):
        return []
    entries: list[tuple[str, str, str, str, str]] = []
    for name in PINNED_COMPONENTS:
        comp = components.get(name)
        if not isinstance(comp, dict) or comp.get("status") != "pinned":
            continue
        entries.append(
            (
                f"manifests/{manifest_path.name}",
                name,
                str(comp.get("repo", "")),
                str(comp.get("ref", "main")),
                str(comp.get("sha", "")),
            )
        )
    return entries


def validate_historical_manifests(root: Path, candidate: str) -> list[str]:
    """Structural check for non-candidate manifests: parseable + well-formed SHAs.

    Historical pins are allowed to differ from live mains; malformed
    entries are still rejected so history stays machine-readable.
    """
    errors: list[str] = []
    for path in sorted((root / "manifests").glob("*.yaml")):
        if path.name == candidate:
            continue
        source = f"manifests/{path.name}"
        try:
            with path.open(encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except (OSError, ValueError) as exc:
            errors.append(f"{source}: unreadable ({exc})")
            continue
        if not isinstance(doc, dict) or not isinstance(doc.get("components"), dict):
            errors.append(f"{source}: not a composition manifest document")
            continue
        for name in PINNED_COMPONENTS:
            comp = doc["components"].get(name)
            if not isinstance(comp, dict) or comp.get("status") != "pinned":
                continue
            sha = comp.get("sha", "")
            if not isinstance(sha, str) or not SHA_RE.match(sha):
                errors.append(f"{source}: '{name}' pin is not a 40-char SHA")
    return errors


def resolve_live_sha(repo: str, ref: str = "main") -> str:
    """Resolve the live SHA of refs/heads/<ref> via git ls-remote."""
    proc = subprocess.run(
        ["git", "ls-remote", repo, f"refs/heads/{ref}"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"git ls-remote failed for {repo}: {proc.stderr.strip()}")
    for line in proc.stdout.splitlines():
        sha, _, _ = line.partition("\t")
        if SHA_RE.match(sha.strip()):
            return sha.strip()
    raise RuntimeError(f"no SHA resolved for {repo} refs/heads/{ref}")


def compare_pins(
    entries: list[tuple[str, str, str, str, str]],
    live: dict[tuple[str, str], str],
) -> list[str]:
    """Pure comparison: entries against {(repo, ref): live_sha}."""
    errors: list[str] = []
    for source, name, repo, ref, sha in entries:
        key = (repo, ref)
        if key not in live:
            errors.append(f"{source}: no live SHA resolved for '{name}' ({repo})")
            continue
        if sha != live[key]:
            errors.append(
                f"{source}: '{name}' pin {sha} != live {ref} {live[key]} ({repo})"
            )
    return errors


def bump_instructions(candidate: str, errors: list[str]) -> str:
    lines = [
        f"PIN-FAIL: candidate manifest '{candidate}' pins are stale. Bump them:",
        "",
    ]
    lines.extend(f"  - {error}" for error in errors)
    lines.extend(
        [
            "",
            "Refresh the CANDIDATE manifest only (never rewrite history):",
            "",
            "  git ls-remote https://github.com/HorneroOS/shell refs/heads/main",
            "  git ls-remote https://github.com/HorneroOS/config refs/heads/main",
            "",
            "Then update the sha/subject fields of manifests/"
            + candidate
            + " per docs/RELEASE_PROCESS.md, and re-run:",
            "  python3 scripts/check-pins.py",
            "",
            "Cutting a new release instead? Copy the candidate to a new",
            "manifest file, repoint manifests/candidate, and update",
            "profiles/ + releases/ (never edit a tagged manifest).",
        ]
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check candidate manifest pins are fresh.")
    parser.add_argument("--root", default=None, help="Repository root")
    parser.add_argument(
        "--manifest",
        default=None,
        help="Candidate manifest filename (default: manifests/candidate pointer)",
    )
    args = parser.parse_args(argv)
    root = Path(args.root) if args.root else Path(__file__).resolve().parent.parent
    try:
        candidate = args.manifest or read_candidate_name(root)
        if args.manifest and not (root / "manifests" / args.manifest).is_file():
            print(f"PIN-FAIL: manifest '{args.manifest}' does not exist")
            return 1
    except RuntimeError as exc:
        print(f"PIN-FAIL: {exc}")
        return 1
    structural = validate_historical_manifests(root, candidate)
    if structural:
        for error in structural:
            print(f"PIN-FAIL: {error}")
        return 1
    entries = manifest_pin_entries(root / "manifests" / candidate)
    if not entries:
        print(f"PIN-FAIL: no pinned shell/config entries in manifests/{candidate}")
        return 1
    live: dict[tuple[str, str], str] = {}
    failures: list[str] = []
    for _, _, repo, ref, _ in entries:
        if (repo, ref) in live:
            continue
        try:
            live[(repo, ref)] = resolve_live_sha(repo, ref)
        except (RuntimeError, subprocess.SubprocessError, OSError) as exc:
            failures.append(f"unresolvable '{repo}' refs/heads/{ref}: {exc}")
    if failures:
        for failure in failures:
            print(f"PIN-FAIL: {failure}")
        print("Re-run with network access to github.com.")
        return 1
    errors = compare_pins(entries, live)
    if errors:
        print(bump_instructions(candidate, errors))
        return 1
    print(f"PIN-PASS: candidate manifests/{candidate} pins match live main SHAs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
