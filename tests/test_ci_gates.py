"""Tests for the track-1 CI gates: triggers, pin-freshness, secrets-lint."""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "composition-ci.yml"


def _load_pins_module():
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "check_pins", ROOT / "scripts" / "check-pins.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_pins = _load_pins_module()

REQUIRED_PATHS = {
    "manifests/**",
    "profiles/**",
    "releases/**",
    "scripts/**",
    "tests/**",
    "cli/**",
    "docs/**",
}


def _workflow_doc():
    with WORKFLOW.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_yaml_parses():
    doc = _workflow_doc()
    assert doc["name"] == "composition-ci"
    assert set(doc["jobs"]) >= {"composition", "pin-freshness", "secrets-lint"}


def test_triggers_cover_cli_docs_and_composition():
    # Push stays path-filtered (minutes), but pull_request must be UNFILTERED:
    # required contexts have to report on every PR or strict protection
    # blocks the merge forever (Track 1).
    doc = _workflow_doc()
    push_paths = set(doc["on"]["push"]["paths"] or [])
    assert REQUIRED_PATHS <= push_paths, f"push paths missing: {REQUIRED_PATHS - push_paths}"
    pr_filter = doc["on"]["pull_request"]
    assert not pr_filter or not pr_filter.get("paths"), (
        "pull_request must not be path-filtered"
    )


def test_markdownlint_covers_docs_glob():
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "docs/*.md" in text


def test_pin_freshness_job_runs_checker():
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "scripts/check-pins.py" in text


def test_secrets_lint_job_runs_scanner():
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "scripts/secrets-lint.sh" in text


def _candidate_entries():
    candidate = _pins.read_candidate_name(ROOT)
    return _pins.manifest_pin_entries(ROOT / "manifests" / candidate)


def test_pin_entries_cover_shell_and_config():
    entries = _candidate_entries()
    assert entries, "no pinned shell/config entries found"
    names = {name for _, name, _, _, _ in entries}
    assert {"shell", "config"} <= names


def test_compare_pins_accepts_fresh():
    entries = _candidate_entries()
    live = {(repo, ref): sha for _, _, repo, ref, sha in entries}
    assert _pins.compare_pins(entries, live) == []


def test_compare_pins_rejects_stale_with_detail():
    entries = [("manifests/x.yaml", "shell", "https://example.test/shell", "main", "0" * 40)]
    live = {("https://example.test/shell", "main"): "1" * 40}
    errors = _pins.compare_pins(entries, live)
    assert len(errors) == 1
    assert "0" * 40 in errors[0] and "1" * 40 in errors[0]


def test_bump_instructions_point_at_bump_process():
    errors = ["manifests/x.yaml: 'shell' pin stale"]
    text = _pins.bump_instructions("x.yaml", errors)
    assert "git ls-remote" in text
    assert "RELEASE_PROCESS" in text
    assert "never rewrite history" in text


def test_secrets_lint_passes_on_clean_tree():
    proc = subprocess.run(
        ["bash", "scripts/secrets-lint.sh"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "SECRETS-PASS" in proc.stdout


def test_allowlist_entries_are_live():
    # Every suppression must match a real current line: no dead entries that
    # could hide drift. Format: path-prefix|fixed-string|reason.
    allowlist = ROOT / "scripts" / "secrets-allowlist.txt"
    assert allowlist.is_file(), "allowlist file missing"
    entries = [
        line.split("|", 2)
        for line in allowlist.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    assert entries, "allowlist is empty"
    for prefix, fixed, reason in entries:
        assert reason.strip(), f"entry without reason: {prefix}"
        candidates = list(ROOT.glob(prefix.rsplit("/", 1)[0] + "/*"))
        assert candidates, f"allowlist path prefix matches nothing: {prefix}"
        found = any(
            fixed in path.read_text(encoding="utf-8", errors="replace")
            for path in candidates
            if path.is_file()
        )
        assert found, f"dead allowlist entry (no live line contains it): {prefix}|{fixed}"


def test_secrets_lint_flags_planted_credential(tmp_path):
    prefix = "gh" + "p_"
    probe = tmp_path / "leak.txt"
    probe.write_text(f"deploy_token = \"{prefix}{'A' * 36}\"\n", encoding="utf-8")
    proc = subprocess.run(
        ["bash", str(ROOT / "scripts" / "secrets-lint.sh"), "--root", str(tmp_path)],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 1
    assert "SECRETS-FAIL" in proc.stdout


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
