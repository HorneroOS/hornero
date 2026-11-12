# Agentic workstation — agents in HorneroOS

Status: implemented in `horneroctl` (this repo), host-validated.
Tracking: hornero#391. Contracts: [adr-agentic-wave1.md](adr-agentic-wave1.md).
Execution ledger: [agentic-execution-ledger.md](agentic-execution-ledger.md).
Javi harness detail: [javi-secure-harness.md](javi-secure-harness.md).

## What is agentic in HorneroOS

HorneroOS does not ship one monolithic agent. It ships a small, truthful
control surface over agents that already exist:

- **Javi** — the built-in assistant, backed by a pinned Hermes gateway
  confined by Hornero (ABAC policy, bubblewrap/systemd sandbox, typed
  broker tools, workspaces, audit log). Disabled by default, never
  required, loopback only. See [javi-secure-harness.md](javi-secure-harness.md).
- **A declarative registry of external agent CLIs** — `javi-hermes`,
  `codex`, `claude-code`, `muse`, and `opencode` described as data
  (executable, discovery, config/skills paths, MCP/ACP shape, session and
  approval semantics). The registry installs, launches, and reads no
  credentials; auth detection is file-presence only.
- **A canonical config registry** that projects your instructions,
  skills, MCP, and ACP intent into those agents (below).
- **Proposals, not execution**, for shell commands and delegation.
- **A staged local installer** for generated plugins.

Nothing in this surface auto-approves a tool call, adds a YOLO flag, or
runs as root.

## Javi vs external agents

| | Javi (Hermes) | External agents (Codex, Claude Code, Muse, OpenCode) |
|---|---|---|
| Owner of the runtime | Pinned upstream Hermes, confined by Hornero | The upstream vendor; you install it yourself |
| Security model | Hornero ABAC + sandbox (see harness doc) | The runtime's own approvals and sandbox |
| Model choice | Configured through the Hermes gateway | Owned by the external runtime, not Hornero |
| Hornero's role | Runs and confines the gateway | Registry, config projection, launch proposals |

Delegating to an external agent never transfers Javi's policy: the
external runtime keeps its own security model and does **not** inherit
Hornero ABAC, bubblewrap, or workspace policy.

## Install and select agents

Hornero never downloads or installs an agent CLI. Install the upstream
tool yourself (OS package or vendor installer), then:

```bash
horneroctl agent list                 # what is registered and found on PATH
horneroctl agent status codex         # one agent in detail
horneroctl agent doctor               # read-only registry/default health
horneroctl agent default set codex --dry-run   # preview; writes nothing
horneroctl agent default set codex --yes       # record the default
horneroctl agent default show                  # read it back
horneroctl agent launch codex                  # dry-run proposal only
```

Recording a default installs and launches nothing. `launch` prints a
proposal; you run the agent yourself in a terminal.

## Agent config registry and companion fragments

One canonical, user-owned registry lives at
`$XDG_CONFIG_HOME/hornero/agent-config.json` (override:
`$HORNERO_AGENT_CONFIG_FILE`). Entries are `instruction`, `skill`,
`mcp`, or `acp`, each targeted at zero or more agent ids.

```bash
horneroctl agent config status        # read-only projection state
horneroctl agent config check         # fail on drift, duplicates, unsupported
horneroctl agent config apply --dry-run
horneroctl agent config apply --yes
```

The truth about projection scope, printed by every command: **only
skills are written to native, auto-discovered agent skill paths**
(`<skills_path>/<id>/SKILL.md`). Instruction, MCP, and ACP outputs are
Hornero-owned **companion fragments** next to the agent's config — the
agents do not load them automatically, ACP is inspection-only, and apply
never merges into an agent's primary config. Apply is idempotent,
records an ownership receipt per file under
`$XDG_STATE_HOME/hornero/agent-config/receipts/`, and backs up a
pre-existing unmanaged file before replacing it (see Recovery).

## Shell proposals and delegation

```bash
horneroctl assistant shell-proposal --command "ls -la"
horneroctl assistant delegate codex --workspace /tmp "review the parser"
```

Both are proposals only: nothing is executed or launched.
`shell-proposal` classifies risk (`read-only`, `mutating`,
`privileged`, `protected` — for example `/usr/bin/sudo rm -rf /` is
`protected`) and leaves the run to you or to the typed broker
(`horneroctl assistant tool`). `delegate` builds on the dry-run launch
proposal, fails closed for an unknown agent id, and states the boundary
plainly: the external runtime keeps its own security model and does not
inherit Hornero ABAC/bubblewrap/workspace policy.

## Plugin install-local

```bash
horneroctl plugin install-local ./my-plugin --dry-run   # writes nothing
horneroctl plugin install-local ./my-plugin --yes
```

Validates and stages a plugin package from a local directory: no
network, no code executed, nothing enabled. Symlinked path components
or entries and any `.git` directory are refused. The receipt records
the absolute source path and the payload SHA-256. Installed QML is
inert data — not loaded, not sandboxed — until you explicitly enable
it, and enabled QML runs with your user privileges.

## Security model and honest limits

- Javi's boundary is OS-level: ABAC decides, bubblewrap/systemd confine
  the whole Hermes process, the gateway is loopback-only with a 0600
  local key, and activity is audit-logged.
- **Hermes residual:** the sandbox shares the network so the gateway
  stays reachable and can reach its model provider, and Hermes can read
  its own home, including its provider credentials. A compromised agent
  could exfiltrate its own key over its provider connection. Treat the
  Hermes home as agent-owned, not as a user secret store. Full detail
  and negative tests: [javi-secure-harness.md](javi-secure-harness.md).
- **External runtimes own their models and their safety.** Hornero does
  not see their prompts, credentials, or session stores, and cannot
  vouch for their approvals or sandboxing.
- **ACP and MCP are transports, not security boundaries.** Projecting
  an MCP or ACP fragment grants nothing by itself.
- Credential contents are never read by the registry; presence only.

## Recovery

- **Backups:** before apply replaces an unmanaged file, the original is
  copied to `$XDG_STATE_HOME/hornero/agent-config/backups/` with a
  collision-proof name. Restore by copying the newest `.bak` for that
  file back over the target.
- **Receipts:** `$XDG_STATE_HOME/hornero/agent-config/receipts/` record
  what Hornero owns (path + content hash). `agent config status`
  reports `drifted` when a managed file changed since the last apply;
  re-run `agent config apply --yes` to re-render, or restore a backup.
- **Remove:** delete the canonical registry entry and re-apply, or
  remove the projected file and its receipt yourself. For plugins,
  `horneroctl plugin remove <id>` removes only receipt-owned packages.
  For Javi, `horneroctl assistant setup --remove --yes` removes only
  unchanged Hornero-owned files; modified or external files stay.

## Acceptance script

`scripts/agentic-acceptance.sh` is the host acceptance for this surface
(no QEMU/ISO). It builds `horneroctl` into a temp dir — or reuses
`HORNEROS_HORNEROCTL_BIN` — runs every assertion against an isolated
temp HOME/XDG with real exit codes, cleans up after itself, and exits
non-zero on the first failed assertion:

```bash
scripts/agentic-acceptance.sh
HORNEROS_HORNEROCTL_BIN=/path/to/horneroctl scripts/agentic-acceptance.sh
systemd-run --user --scope -p MemoryMax=2G -p MemorySwapMax=0 \
  -p CPUQuota=200% -- scripts/agentic-acceptance.sh   # capped run
```

It covers `agent list`, the default set/show round-trip, the full
`agent config` lifecycle (dry-run writes nothing, apply writes a skill
plus receipt, second apply is unchanged, a hand edit reports drift,
and a pre-existing unmanaged skill is recoverable from the newest
backup), shell-proposal non-execution and protected classification,
delegate truthfulness, `plugin install-local --dry-run` writing
nothing, and a resource section that times `agent list` and
`assistant shell-proposal` (`/usr/bin/time -v` when available) and
prints the binary size.
