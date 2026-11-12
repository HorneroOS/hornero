# Agentic execution ledger — Wave 0+1

Updated: 2026-11-12. Base: hornero `origin/main` c9aed3d.
Contracts: [adr-agentic-wave1.md](adr-agentic-wave1.md).
Status key: verified = code on main + host-validated; contract = this
wave's docs only; missing = no code; blocked = needs a named decision.

| Workflow | Definition (source) | Issues / PRs | Status | Next gate |
|---|---|---|---|---|
| A — Multi-agent registry | `AssistantAgent` registry + selector (core audit) | hornero#154 (M3); no dedicated issue yet — file one before code | contract (ADR §1) | Sandbox-home decision (per-agent unit vs shared gateway) blocks `launch` |
| B — Knowledge vault | Extend `assistant_knowledge_*` snapshot to broker catalogue (core audit) | hornero#191 OPEN (needs-triage; slice 1 merged, tracking stale) | partial: 7-tool snapshot verified; 12-tool vault contract (ADR §3) | Triage #191 against ADR §3 doc set |
| C — Typed horneroctl JSON contract | `schemaVersion` + documented `data.<key>` JSON-string convention (derived: shell audit prerequisite) | none yet — file with A | contract (ADR §2) | Owner confirms C is a standalone workflow |
| D — Per-agent sandbox homes | One unit/home per agent vs shared gateway (derived: ADR §1 open decision) | hornero#374/#386/#387 merged (single-Hermes harness — do not rebuild) | blocked (decision) | User picks (a) per-agent units or (b) shared gateway |
| E — Agent Center UI | Shell pane over horneroctl JSON (shell audit, conditional mapping) | shell: no agent pane on main (28 panes, none agent/workflow) | not started; do not build this wave | A+C shipped with versioned JSON; no fake buttons |
| F — Plugin/extension ecosystem | Shell-surface widgets only; no agent tools/principals (shell audit, conditional mapping) | plugins catalog on main; hornero#154 M2 | verified for widgets; agent-extension claims prohibited (ADR §4) | Registry production key `/etc/hornero/registry.pub` not shipped |

## Already verified on main (Wave 0 — do not rebuild)

ABAC (`assistant_policy_decide/delegate`), bubblewrap gateway
(`assistant_gateway_bwrap_argv`), broker (12 typed tools), workspaces,
SOUL/profile, sessions, models, audit log, setup receipts, 7-tool
knowledge snapshot — hornero#374/#386/#387, `docs/javi-secure-harness.md`.

Not deployed (user decision, not code): live gateway migration from the
legacy systemd-only unit, shell rollout, provider-catalogue picker.

## Open items needing owner confirmation

1. Workflows C and D are derived from the audits, not named in the
   mission input; E/F mapping is conditional (Agent Center / plugins).
2. hornero#191 and #154 remain OPEN despite merged slices — close or
   re-scope during Wave 1 triage, do not treat as blockers for ADR work.
3. No V tests were run for this docs-only change; implementation waves
   must run `v test` under the workspace V rules.
