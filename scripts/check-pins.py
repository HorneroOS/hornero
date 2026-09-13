#!/usr/bin/env python3
"""Cross-gate: manifest pins must equal live main SHAs of shell+config.

Usage:
    python3 scripts/check-pins.py [--root DIR]

Resolves the current ``main`` SHA of every pinned ``shell``/``config``
component via ``git ls-remote`` and compares it with the ``sha``
recorded in ``manifests/*.yaml``. Exit 0 when every pin is fresh,
1 otherwise (with bump instructions).

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


def manifest_pin_entries(root: Path) -> list[tuple[str, str, str, str, str]]:
    """Return (manifest_file, component, repo, ref, sha) for shell/config pins."""
    entries: list[tuple[str, str, str, str, str]] = []
    for path in sorted((root / "manifests").glob("*.yaml")):
        with path.open(encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
        if not isinstance(doc, dict):
            continue
        components = doc.get("components")
        if not isinstance(components, dict):
            continue
        for name in PINNED_COMPONENTS:
            comp = components.get(name)
            if not isinstance(comp, dict) or comp.get("status") != "pinned":
                continue
            entries.append(
                (
                    f"manifests/{path.name}",
                    name,
                    str(comp.get("repo", "")),
                    str(comp.get("ref", "main")),
                    str(comp.get("sha", "")),
                )
            )
    return entries


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


def bump_instructions(errors: list[str]) -> str:
    lines = [
        "PIN-FAIL: manifest pins are stale. Bump them:",
        "",
    ]
    lines.extend(f"  - {error}" for error in errors)
    lines.extend(
        [
            "",
            "To bump, resolve the live SHAs yourself (never invent one):",
            "",
            "  git ls-remote https://github.com/HorneroOS/shell refs/heads/main",
            "  git ls-remote https://github.com/HorneroOS/config refs/heads/main",
            "",
            "Then copy the newest manifest in manifests/, update name, date,",
            "and the sha/subject fields per docs/RELEASE_PROCESS.md, and",
            "re-run: python3 scripts/check-pins.py",
        ]
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check manifest pins are fresh.")
    parser.add_argument("--root", default=None, help="Repository root")
    args = parser.parse_args(argv)
    root = Path(args.root) if args.root else Path(__file__).resolve().parent.parent
    entries = manifest_pin_entries(root)
    if not entries:
        print("PIN-FAIL: no pinned shell/config entries found in manifests/*.yaml")
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
        print(bump_instructions(errors))
        return 1
    print(f"PIN-PASS: {len(entries)} pin(s) match live main SHAs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
