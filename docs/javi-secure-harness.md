# Javi secure harness

Status: implemented in horneroctl (this repo), host-validated on Arch/Hyprland.
Hermes compatibility: pinned `f14699a1379838862d3020b97785796aa555d36d`
(the revision `assistant.v` negotiates against; verified live with
`hermes --version`).

## Boundary

Hermes' own `SECURITY.md` §2.2 states the only security boundary against an
adversarial LLM is OS-level isolation; approvals, allowlists and scanners
inside the agent process are heuristics. Hornero therefore confines the
**whole Hermes process**, not just its terminal tool:

- The `hornero-hermes.service` user unit horneroctl writes now carries
  systemd hardening (`NoNewPrivileges`, `PrivateTmp`,
  `ProtectKernelTunables`, `ProtectControlGroups`, `RestrictSUIDSGID`,
  `LockPersonality`, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`,
  empty `CapabilityBoundingSet`).
- When `bwrap` (bubblewrap) is on PATH, the unit execs Hermes through it:
  host root read-only, `$HOME` masked by tmpfs, and only `~/.hermes`, the
  pinned Hermes venv (read-only via the root bind) and the active Javi
  workspace bound back. `$XDG_RUNTIME_DIR` is masked, so the Wayland
  compositor socket and the session D-Bus socket are unreachable: grim,
  wl-paste and any compositor client fail inside the sandbox even though
  their binaries are visible. This also confines `execute_code`, MCP
  subprocesses and in-process plugins/skills, which terminal-backend
  isolation alone does not.
- Without bwrap the profile is reported as `systemd-only (not sandboxed)`
  in the unit description and in `assistant gateway status --json`
  (`isolation` field). It is never labelled sandboxed.

Residual risks, stated plainly:

- Network is shared (`--share-net`): the gateway must stay reachable on
  loopback and reach the configured model provider. Kernel-level egress
  filtering is future work; `network.request` is governed at the ABAC/tool
  layer today.
- The agent can read anything bound into the sandbox, including
  `~/.hermes/auth.json` (its own provider credentials). Provider keys are
  never exposed to QML or horneroctl output, but a compromised agent could
  exfiltrate its own key over its provider connection. Treat the Hermes
  home as agent-owned, not as a user secret store.
- Same-UID loopback: horneroctl authenticates to the gateway with the
  0600 Bearer key; any process running as the user outside the sandbox
  could read that key file. This is the user's own trust envelope, not
  the agent boundary.

Host negative tests (disposable fake HOME, synthetic secret): reading a
secret outside the workspace, writing outside the workspace, grim
screenshot, wl-paste clipboard read and `sudo` all fail inside the exact
bwrap view the unit generates; workspace and `~/.hermes` writes succeed.

## ABAC policy

`horneroctl assistant policy` is the trusted decision point. It lives in
horneroctl, outside Hermes; no prompt, skill, memory or tool output can
change a decision. The policy file (`~/.config/hornero/assistant-policy.json`,
0600) sits outside the sandbox bind set, and filesystem writes to it are
hard-denied for the agent principal.

Model: `Principal + Action + Resource + Context -> ALLOW | DENY |
REQUIRE_APPROVAL`, evaluated by `assistant_policy_decide`:

1. Unknown principal/action, or a policy that fails validation -> DENY.
2. Hard system denies (protected paths such as `~/.ssh`, `~/.gnupg`,
   `~/.hermes/auth.json`, browser profiles, keyrings, the assistant key
   and the policy file; unattended `shell.execute`; `package.remove`)
   -> DENY. No user rule can override these.
3. Matching explicit DENY -> DENY (deny overrides allow).
4. Matching REQUIRE_APPROVAL -> allowed only with an unexpired approval
   bound to the exact action and resource; otherwise REQUIRE_APPROVAL.
5. Matching ALLOW -> ALLOW. Otherwise default DENY.

Modes cap principals further: Ask mode is read-only, Chat mode has no
machine authority, and switching modes never widens permissions.
Delegation is intersection-only: `assistant_policy_delegate` gives a
subagent at most the parent's allows, and always carries the parent's
denies. Wildcards in principal/action are rejected at validation.

Presets (`assistant policy preset <name> --yes`): `read-only` (default),
`workspace-agent`, `desktop-assistant`. `revoke-all --yes` restores
`read-only` immediately. `check <action> <resource>` simulates one
decision against the active workspace (the Control Center policy
simulator uses the same contract).

A typed evaluator is used instead of Cedar/OPA: the action catalogue is
fixed and resources are paths/domains/units, so a Rego/Cedar runtime
would add a native dependency to every install for no extra
expressiveness on this subset. The semantics above are pinned by
`assistant_policy_test.v`, including symlink-escape and traversal cases
(canonicalisation resolves symlinks on the existing path prefix, so a
workspace symlink cannot escape the workspace).

## Workspaces

`horneroctl assistant workspace` manages the agent's only default write
scope: roots under `$XDG_DATA_HOME/hornero/javi-workspaces/` (never
`$HOME`), a registry at `~/.config/hornero/workspaces.json` (outside the
sandbox), per-workspace `AGENTS.md` instructions, and `reveal` for the
user. The gateway unit binds exactly the active workspace.

## Capability broker, modes and prompt

`horneroctl assistant tool <name>` is the only mediated host surface:
typed tools (`system_info`, appearance/theme read, `theme_set`,
`window_list`, `window_focus`, `notify`, `screenshot`), each mapped to
one ABAC action/resource, decided before execution, audit-logged either
way. There is no generic command/shell tool. Screenshot runs in trusted
horneroctl via `grim`, writes only inside the active workspace, and is
denied/`require_approval` under the default presets.

Session modes cap authority before policy: Ask is read-only and
auto-denies approvals, Chat has no machine authority, Agent uses the
full policy. Switching modes never widens permissions
(`assistant.v`: `assistant_session_effective_mode`,
`assistant_mode_escalates`).

The full user-configurable system prompt is Hermes' `SOUL.md`, edited
through `assistant prompt` with horneroctl-side version snapshots and
rollback. It changes behaviour only: policy, hard denies and sandbox
binds are outside prompt text and cannot be overridden by it.

Audit is the append-only, redacted TSV at
`~/.config/hornero/assistant.log` (0600, bounded rotation): broker
calls with their policy outcome, approvals, policy preset/revoke,
prompt/model/workspace changes and ask/stop events. Prompts, answers
and secrets are never written.

## Threat model (STRIDE + agentic, incremental)

Trust boundaries: user/Control Center ↔ horneroctl (trusted, user
UID); horneroctl ↔ Hermes gateway (loopback + 0600 Bearer key, same
UID); Hermes process ↔ host (bubblewrap when the installed unit uses
it); LLM/tool output ↔ policy (output is data, never authority).

| Threat | IDs | Evidence / mitigation | Acceptance criterion | Residual |
|---|---|---|---|---|
| Agent reads user secrets outside workspace | I, E / LLM06, LLM08 | bwrap masks `$HOME`; only `~/.hermes` + active workspace bound; ABAC hard-denies protected paths | Disposable-home negative test: synthetic secret read fails inside the generated bwrap view | Live gateway is unsandboxed until its legacy unit is migrated (status reports `systemd-only (not sandboxed)`) |
| Prompt/tool-output injection grants authority | T, E / LLM01, AGNT02, AGNT06 | Decisions only in horneroctl `assistant_policy_decide`; prompt (`SOUL.md`) cannot change policy; broker ignores instructions in tool output | Policy `check` unchanged after prompt set/rollback (host-verified) | Malicious content can still mislead the LLM's wording, not its authority |
| Screenshot/clipboard exfiltration | I / LLM06, AGNT04 | `$XDG_RUNTIME_DIR` masked in sandbox; screenshot only via broker, approval-gated, workspace-only output | `grim`/`wl-paste` fail in sandbox; broker screenshot denied without approval, succeeds scoped with it | Approved screenshots capture what the user approved; review before approving |
| Approval replay / argument swap | S, T / AGNT01 | Approvals bound to exact action+resource+expiry in policy context; Ask/Chat auto-deny | Policy tests: expired and mismatched-resource approvals denied | Same-UID local processes are inside the user's trust envelope |
| Isolation overclaim | — / LLM09 | `assistant_gateway_effective_isolation` derives the label from the installed unit's `ExecStart` (basename `bwrap`), not PATH capability (#379) | Legacy unit reports `systemd-only (not sandboxed)` live; spoofed `~/bwrap-notes/hermes` path stays unsandboxed in tests | — |
| Delegated subagent escalation | E / LLM08, AGNT05 | `assistant_policy_delegate` is intersection-only and carries parent denies | Policy tests: delegate cannot gain an action the parent lacks | — |
| Credential exposure via UI/logs | I / LLM06 | Provider keys stay in Hermes home; QML never receives them; audit log redacts secrets and stores no prompts/answers | `assistant model show` prints model/provider only; log fields pass `redact_secrets` | A compromised agent can misuse its own provider key over its provider connection |
| Network egress of protected data | I / AGNT04 | `--share-net` today; `network.request` governed at ABAC/tool layer only | Documented, not kernel-enforced | **Open:** kernel egress filtering is future work |

Not assessed: malicious MCP servers/plugins beyond process confinement
(they run inside the same bubblewrap view; per-plugin authority is the
broker/policy layer, and new skills/MCP must not inherit host access
outside that view).

## Status report (2026-11-10, host-verified)

Merged: hornero #374 (harness), #375–#377 (prompt/binds), #378
(model show/set), #379 (effective isolation), #380 (threat model),
#381 (audit `--filter`), #382 (session↔workspace keys), #383
(workspace ids), #384 (binds, 121 chains); shell #353–#355 (Control
Center security/prompt/model), #356 (model chips), #357 (workspace
manager); docs #103 (architecture).

Measurements on the development host: horneroctl static binary
16.2 MB; the (legacy, unsandboxed) Hermes gateway idles at ~246 MB
RSS — that is Hermes itself; with Javi disabled horneroctl starts
nothing and the desktop is unaffected (`assistant disable --dry-run`
touches only `assistant.json`).

Scenario evidence so far: E/F/G/H and the negative set were proven
with disposable homes/workspaces and synthetic secrets (secret read,
write-outside, symlink escape, `grim`, `wl-paste`, `sudo` all fail
inside the generated bwrap view; broker screenshot denied without
approval and scoped with it; prompt set/rollback leaves policy
decisions unchanged; preset→revoke flips `policy check` immediately).
I is implemented (#382) and unit/host verified with isolated
registries. A/B/C/D/J still need the live gateway: they are blocked
on the user decision below, not on code.

Open, explicitly:

- **Live gateway migration (user decision).** The running gateway
  still uses a legacy pre-harness unit; horneroctl honestly reports
  `systemd-only (not sandboxed)`. Migrating means backing up that
  unit, `assistant gateway start --yes`, and a brief gateway restart.
  Not done without the user's go-ahead.
- **Shell deployment (user decision).** The host's
  `~/.config/quickshell` checkout predates the Javi shell PRs;
  updating it is a desktop-wide change plus shell restart.
- **Kernel network egress.** Still `--share-net`; filtering needs a
  root-owned mechanism (nft per-UID or a netns proxy) and is future
  work, governed today only at the ABAC/tool layer.
- LLM-driven scenarios A/B/C/D/J and a provider-catalogue picker
  beyond gateway-reported models.
