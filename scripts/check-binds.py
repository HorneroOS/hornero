#!/usr/bin/env python3
"""Bind audit (hornero#61): every `horneroctl` invocation reachable from
keybinds, autostart, .desktop launchers, first-boot scripts, and shell
QML must resolve against the CLI — no silent no-op keys.

Usage:
  scripts/check-binds.py --binary BIN --shell-dir S --config-dir C
  scripts/check-binds.py --refresh --binary BIN --shell-dir S --config-dir C

The gate extracts used verb chains from the shell/config trees, probes
each as `BIN <chain> --help` (exit 0 = handled, no side effects: help
short-circuits before any action), and diffs the used set against the
committed manifest `binds/invocations.txt`. `--refresh` rewrites the
manifest instead of failing on drift. Exit 0 = all handled, no drift;
exit 1 names the offenders.

Scanned suffixes: *.conf (hypr binds, exec-once), *.sh, *.desktop
(Exec=), *.qml (`"horneroctl", "verb", ...` arrays and `sh -c` backtick
bodies). `//` and `#` line comments are stripped before matching;
`/* */` blocks, escaped backticks, and commands built purely at
runtime are out of scope.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "binds" / "invocations.txt"

CONF_SUFFIXES = {".conf"}
SCRIPT_SUFFIXES = {".sh", ".desktop"}
QML_SUFFIXES = {".qml"}

# Bare form: `horneroctl verb ...` up to a shell operator, quote,
# redirection, assignment, or comment. Flags are cut in post-processing
# (first `-` token ends the chain), so `shell ipc -- call lock` audits
# as `shell ipc`.
BARE_RE = re.compile(r"horneroctl((?:\s+[^\s#&|;'\"`()=><%,$]+)+)")
# QML array form: `"horneroctl", "verb", ...` (QML variables are unquoted
# and skipped, so `apply(name)` audits as the static prefix).
ARRAY_RE = re.compile(r'"horneroctl"((?:\s*,\s*"[^"]*")*)')
QUOTED_RE = re.compile(r'"([^"]*)"')


def strip_comments(text: str, suffix: str) -> str:
    out = []
    for line in text.splitlines():
        if suffix in QML_SUFFIXES:
            line = line.split("//", 1)[0]
        else:
            line = line.split("#", 1)[0]
        out.append(line)
    return "\n".join(out)


def chain_of(tokens: list) -> str:
    keep = []
    for tok in tokens:
        if tok.startswith("-") or tok in ("--",):
            break
        keep.append(tok)
    return " ".join(keep)


# Extraction is positional, not textual: prose inside qsTr/console
# strings ("horneroctl did not respond") must never become chains.
#   .conf     bind/exec lines only (keybinds, exec-once, bindle)
#   .desktop  Exec= lines only
#   .sh       command position only (bare call, VAR= assignments, exec)
#   .qml      `"horneroctl", "verb", ...` arrays plus `sh -c` backtick
#             script bodies (shell lines inside them)
CONF_GATE_RE = re.compile(r"\b(bindl?e?|exec(-once)?)\b[^#\n]*horneroctl")
DESKTOP_GATE_RE = re.compile(r"^\s*Exec\s*=")
SH_GATE_RE = re.compile(r"^\s*(?:[A-Za-z_]+=\S+\s+)*(?:exec\s+|sudo\s+)?horneroctl\b")
# QML-embedded shell scripts: `command: ["sh", "-c", `...`]`. Escaped
# backticks inside are out of scope (none in tree as of Preview 9).
SHC_RE = re.compile(r'\["(?:sh|bash)",\s*"-c",\s*`(.*?)`', re.DOTALL)


def chains_in_file(path: Path) -> set:
    try:
        text = strip_comments(path.read_text(encoding="utf-8", errors="ignore"),
                              path.suffix)
    except OSError:
        return set()
    found = set()
    suffix = path.suffix
    for line in text.splitlines():
        if suffix in CONF_SUFFIXES:
            if not CONF_GATE_RE.search(line):
                continue
        elif suffix in SCRIPT_SUFFIXES:
            if suffix == ".desktop":
                if not DESKTOP_GATE_RE.search(line):
                    continue
            elif not SH_GATE_RE.search(line):
                continue
        else:
            continue
        for m in BARE_RE.finditer(line):
            chain = chain_of(m.group(1).split())
            if chain:
                found.add(chain)
    if path.suffix in QML_SUFFIXES:
        for line in text.splitlines():
            for m in ARRAY_RE.finditer(line):
                toks = [t for t in QUOTED_RE.findall(m.group(1)) if t]
                chain = chain_of(toks)
                if chain:
                    found.add(chain)
        for block in SHC_RE.finditer(text):
            for line in block.group(1).splitlines():
                if not SH_GATE_RE.search(line):
                    continue
                for m in BARE_RE.finditer(line):
                    chain = chain_of(m.group(1).split())
                    if chain:
                        found.add(chain)
        return found
    for line in text.splitlines():
        if suffix in CONF_SUFFIXES:
            if not CONF_GATE_RE.search(line):
                continue
        elif suffix in SCRIPT_SUFFIXES:
            if suffix == ".desktop":
                if not DESKTOP_GATE_RE.search(line):
                    continue
            elif not SH_GATE_RE.search(line):
                continue
        for m in BARE_RE.finditer(line):
            chain = chain_of(m.group(1).split())
            if chain:
                found.add(chain)
    return found


# Test trees narrate about commands in prose and fixtures ("horneroctl
# did not respond"); they mirror real sites instead of adding new ones,
# so they are out of scope for the used set.
TEST_HINTS = ("test", "tests", "fixtures", "snapshots")


def collect(shell_dir: Path, config_dir: Path) -> set:
    suffixes = CONF_SUFFIXES | SCRIPT_SUFFIXES | QML_SUFFIXES
    found = set()
    for base in (shell_dir, config_dir):
        if not base.is_dir():
            print(f"missing tree: {base}", file=sys.stderr)
            sys.exit(2)
        for path in sorted(base.rglob("*")):
            if not (path.is_file() and path.suffix in suffixes):
                continue
            # Hints match repo-relative parts only: absolute parents
            # (pytest tmp dirs, user checkouts named *test*) must not
            # exclude real trees.
            rel = path.relative_to(base)
            if any(h in part for part in rel.parts for h in TEST_HINTS):
                continue
            found |= chains_in_file(path)
    return found


def handled(binary: str, chain: str) -> bool:
    try:
        proc = subprocess.run([binary, *chain.split(), "--help"],
                              capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0


def read_manifest(manifest: Path) -> set:
    if not manifest.exists():
        return set()
    return {ln.strip() for ln in manifest.read_text().splitlines()
            if ln.strip() and not ln.startswith("#")}


def write_manifest(manifest: Path, chains: set) -> None:
    manifest.parent.mkdir(exist_ok=True)
    lines = ["# HorneroOS bind audit: every `horneroctl` invocation reachable",
             "# from keybinds, autostart, .desktop launchers, first-boot",
             "# scripts, and shell QML. One verb chain per line, sorted.",
             "# Refresh: python3 scripts/check-binds.py --refresh \\",
             "#   --binary cli/build/horneroctl --shell-dir <shell> --config-dir <config>",
             "# The gate fails on unhandled chains and on drift vs this file.",
             ""]
    lines += sorted(chains)
    manifest.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", required=True)
    ap.add_argument("--shell-dir", required=True)
    ap.add_argument("--config-dir", required=True)
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--manifest", default=str(MANIFEST))
    args = ap.parse_args()
    manifest_path = Path(args.manifest)

    used = collect(Path(args.shell_dir), Path(args.config_dir))
    if args.refresh:
        write_manifest(manifest_path, used)
        print(f"REFRESH: {len(used)} chains in {manifest_path}")
        return 0

    bad = sorted(c for c in used if not handled(args.binary, c))
    if bad:
        print("BIND-AUDIT-FAIL: unhandled horneroctl chains:")
        for c in bad:
            print(f"  horneroctl {c}")
        return 1

    manifest = read_manifest(manifest_path)
    if used != manifest:
        print("BIND-AUDIT-FAIL: manifest drift "
              f"(used={len(used)} manifest={len(manifest)}):")
        for c in sorted(used - manifest):
            print(f"  + horneroctl {c}")
        for c in sorted(manifest - used):
            print(f"  - horneroctl {c}")
        print("Re-run with --refresh and commit binds/invocations.txt.")
        return 1

    print(f"BIND-AUDIT-PASS: {len(used)} chains handled, manifest in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
