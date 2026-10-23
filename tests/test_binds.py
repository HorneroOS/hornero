"""Bind audit gate: fails on unhandled invocations and manifest drift.

Runs scripts/check-binds.py against fixture trees with a stub binary
(no compositor, network, or real horneroctl) and a sandboxed manifest.
"""
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "check-binds.py"

STUB = """#!/bin/sh
# Stub horneroctl: only the `nope` chain is unhandled.
for a in "$@"; do
  if [ "$a" = "nope" ]; then
    echo "unknown command" >&2
    exit 1
  fi
done
exit 0
"""

SHELL_FILES = {
    "modules/x/Panel.qml": 'command: ["horneroctl", "shell", "start"],\n',
}
CONFIG_FILES = {
    "desktop/hypr/hyprland.conf.d/keybindings.conf":
        "bind = CTRL, Space, exec, horneroctl apps launch\n",
    # Lua-era entrypoint (hornero#177): exec_cmd strings, dispatcher
    # strings and table-form argv must all reach the audit, while
    # prose mentioning horneroctl must not.
    "desktop/hypr/hyprland.lua.d/autostart.lua":
        'hl.exec_cmd("horneroctl shell ipc -- call lock")\n'
        'hl.exec_cmd(\n  "horneroctl package updates"\n)\n'
        'os.execute([=[\nhorneroctl system info\n]=])\n'
        'local msg = "horneroctl did not respond"\n',
    "desktop/hypr/hyprland.lua.d/binds.lua":
        'hl.bind("SUPER + W", hl.dsp.exec_cmd("horneroctl welcome open"))\n'
        'hl.bind("SUPER + T", {"horneroctl", "terminal", "open"})\n'
        '--[=[ hl.exec_cmd("horneroctl nope long comment") ]=]\n'
        '-- hl.exec_cmd("horneroctl nope commented")\n',
}


def _tree(base: Path, files: dict) -> None:
    for rel, content in files.items():
        p = base / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")


def _run(tmp_path: Path, *extra: str) -> subprocess.CompletedProcess:
    shell = tmp_path / "shell"
    config = tmp_path / "config"
    binary = tmp_path / "horneroctl"
    manifest = tmp_path / "invocations.txt"
    _tree(shell, SHELL_FILES)
    _tree(config, CONFIG_FILES)
    binary.write_text(STUB, encoding="utf-8")
    binary.chmod(binary.stat().st_mode | stat.S_IXUSR)
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--binary", str(binary),
         "--shell-dir", str(shell), "--config-dir", str(config),
         "--manifest", str(manifest), *extra],
        capture_output=True, text=True)


def test_binds_pass_when_handled_and_in_sync(tmp_path):
    first = _run(tmp_path, "--refresh")
    assert first.returncode == 0, first.stderr
    assert "REFRESH: 7 chains" in first.stdout
    manifest = (tmp_path / "invocations.txt").read_text()
    # Lua forms extracted: exec_cmd bare chain (flags cut), dsp
    # string, and table argv. Prose and commented horneroctl stay out.
    for chain in ("shell start", "apps launch", "shell ipc",
                  "welcome open", "terminal open", "package updates",
                  "system info"):
        assert f"\n{chain}\n" in f"\n{manifest}"
    assert "did not respond" not in manifest
    assert "nope commented" not in manifest
    second = _run(tmp_path)
    assert second.returncode == 0, second.stdout
    assert "BIND-AUDIT-PASS: 7 chains" in second.stdout


def test_binds_fail_on_unhandled_lua_chain(tmp_path):
    _run(tmp_path, "--refresh")
    config = tmp_path / "config"
    _tree(config, {
        "desktop/hypr/hyprland.lua.d/broken.lua":
            'hl.bind("SUPER + X", hl.dsp.exec_cmd("horneroctl nope bad"))\n'
            'hl.exec_cmd(\n  "horneroctl nope multiline"\n)\n'
            'os.execute([=[horneroctl nope long-delimiter]=])\n',
    })
    proc = _run(tmp_path)
    assert proc.returncode == 1
    assert "BIND-AUDIT-FAIL: unhandled" in proc.stdout
    assert "horneroctl nope bad" in proc.stdout
    assert "horneroctl nope multiline" in proc.stdout
    assert "horneroctl nope long-delimiter" in proc.stdout


def test_binds_fail_on_unhandled_chain(tmp_path):
    _run(tmp_path, "--refresh")
    shell = tmp_path / "shell"
    _tree(shell, {
        "modules/x/Broken.qml": 'command: ["horneroctl", "nope", "bad"],\n',
    })
    proc = _run(tmp_path)
    assert proc.returncode == 1
    assert "BIND-AUDIT-FAIL: unhandled" in proc.stdout
    assert "horneroctl nope bad" in proc.stdout


def test_binds_fail_on_manifest_drift(tmp_path):
    _run(tmp_path, "--refresh")
    (tmp_path / "invocations.txt").write_text(
        "# stale\nshell start\n", encoding="utf-8")
    proc = _run(tmp_path)
    assert proc.returncode == 1
    assert "manifest drift" in proc.stdout
    assert "+ horneroctl apps launch" in proc.stdout
