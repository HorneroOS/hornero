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
