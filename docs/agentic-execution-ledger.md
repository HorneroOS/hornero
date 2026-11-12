# Agentic execution ledger — Waves 1–4

Updated: 2026-11-12. Tracking issue: hornero#391.
Contracts: [adr-agentic-wave1.md](adr-agentic-wave1.md).
Status key: verified = code on main + host-validated; pending = no real
evidence yet (never reported as PASS).

## Shipped workflows

| Workflow | What shipped | PRs | Status |
|---|---|---|---|
| A — Multi-agent registry | `horneroctl agent list/status/doctor/default/launch` (launch is dry-run proposal); >=5 runtimes with truthful capability-limited adapters | hornero#390 | verified |
| B — Knowledge vault | `assistant knowledge` bounded, provenance-stamped snapshot; generated vs user-authored separation; no secret/private ingestion | hornero#389 | verified |
| C — Canonical instructions/skills/MCP/ACP | `horneroctl agent config status/check/apply`: one canonical registry, native renderers, ownership receipts, collision-proof backups, duplicate + unsupported detection, idempotent apply; fail-closed on unsafe ids, symlinked skills bases, malformed targets; parse errors never echo registry content | hornero#393 | verified |
| D — Javi orchestration | Pre-existing Ask/Chat/Agent modes (#374/#386/#387, not rebuilt) + `assistant shell-proposal` (never executes; conservative risk classifier) + `assistant delegate` (truthful external-runtime handoff, no ABAC inheritance claim) | hornero#394 | verified |
| E — Agent Center UI | Control Center `agents` pane over real `horneroctl` JSON only; honest not-reported states, Launch = proposal; VM panel screenshot matrix covers 29 panes | shell#364 | verified (host tests); real session QA pending |
| F — Extensions/workflows | Existing plugin lifecycle retained + `plugin install-local`: staged, validator-gated, symlink/VCS fail-closed, payload-SHA receipt, inert (never loaded/enabled) | hornero#395 | verified |

Wave 1 contracts and this ledger's first version: hornero#392.

## Host acceptance evidence (merged main, 2026-11-12)

Built `horneroctl` from main `a35f20b` under
`systemd-run --user --scope -p MemoryMax=2G -p MemorySwapMax=0 -p CPUQuota=200%`
and ran it with an isolated HOME:

- `agent list` discovers javi-hermes/codex/claude-code/muse/opencode on
  this host; `agent default show` reports `not-selected` truthfully.
- `agent config status` on an empty registry reports nothing to project
  and prints the projection-scope note (only skills are native).
- `assistant shell-proposal --command "touch <marker>"` returns
  `executed=false`; the marker file does not exist afterwards.
- `assistant shell-proposal --command "/usr/bin/sudo rm -rf /"` classifies
  `risk: protected`.
- `assistant delegate nope` fails closed; `assistant delegate codex`
  returns a proposal stating the external runtime keeps its own security
  model and does not inherit Hornero ABAC/bubblewrap policy.
- `plugin install-local <dir> --dry-run` writes nothing and states QML is
  inert, not loaded or sandboxed.
- Focused V/pytest suites and full CI (`horneroctl`) passed for #393,
  #394, #395; shell `tests`, `qml`, `lint`, `build` passed for shell#364.

## Wave 4 — host acceptance script and user doc

- Script: `scripts/agentic-acceptance.sh` — builds `horneroctl` into a
  temp dir (or reuses `$HORNEROS_HORNEROCTL_BIN`), runs all assertions
  against an isolated temp HOME/XDG with real exit codes, cleans up,
  and exits non-zero on the first failed assertion. User doc:
  [agentic-workstation.md](agentic-workstation.md).
- Run on this dev workstation (AMD Ryzen 9 5900X, Linux
  7.2.14-arch1-1) under `systemd-run --user --scope
  -p MemoryMax=2G -p MemorySwapMax=0 -p CPUQuota=200%`, script exit 0:
  `agent list` elapsed 4 ms, `assistant shell-proposal` elapsed 4 ms,
  max RSS unavailable from the script on this host (`/usr/bin/time`
  not installed; the script uses it when present), `horneroctl`
  binary size 9,853,928 bytes. All lifecycle assertions held:
  default set/show round-trip, config dry-run writes nothing, apply
  writes a skill plus receipt, second apply unchanged, hand edit
  reports drift, original unmanaged skill recovered from the newest
  backup, shell-proposal marker never created, protected
  classification, delegate unknown-id failure and no-ABAC-inheritance
  statement, plugin install-local dry-run writes nothing.

## Acceptance matrix — still pending real evidence (not PASS)

- Real Preview VM/session: Agent Center in a live shell session, Javi
  gateway round-trip, ArtCraft scenarios (qa#36, installer#36, shell#333
  remain open for this evidence by design).
- Cancellation of a running backend process from the UI, delegation to a
  live external harness session, and idle resource measurements.
- Sandbox-home decision for per-agent units vs shared gateway (Workflow D
  residual in the Wave 1 ADR) — unchanged, needs an owner decision.

## Already verified before this mission (do not rebuild)

ABAC (`assistant_policy_decide/delegate`), bubblewrap gateway, typed
broker tools, workspaces, SOUL/profile, sessions, models, audit log,
setup receipts — hornero#374/#386/#387, `docs/javi-secure-harness.md`.
External runtimes keep their own security models; ACP/MCP are transports,
not security boundaries.
