# ADR: Agentic Wave 1 contracts (registry, horneroctl surface, knowledge vault)

Status: proposed (Wave 1 contract only — no implementation in this change)
Base: `origin/main` c9aed3d (hornero#374/#386/#387 merged). Supersedes nothing.
Scope guard: do not rebuild the Javi secure harness (ABAC, bubblewrap,
broker, workspaces, SOUL, sessions, models, audit in
`cli/modules/hornero_core/assistant*.v`, `docs/javi-secure-harness.md`).
Out of scope: `cli` studio sections, `editions/catalogue.yaml`,
installer/shell/qa trees, QEMU/ISO, live-gateway migration (user decision).

## 1. Agent registry (new, mirrors workspace/session patterns)

> Scope clarification (coordinator): this section defines the *internal*
> Javi sub-agent/principal registry, which belongs to the Javi
> orchestration work (Workflow D) and is not yet implemented. The
> *external* multi-runtime registry (Workflow A: Javi/Hermes, Codex,
> Claude Code, Muse, OpenCode discovery/default/launch proposals)
> shipped separately in HorneroOS/hornero#390 as
> `cli/modules/hornero_core/agent_registry.v` with the top-level
> `horneroctl agent` surface. The two registries share no file or
> command surface; neither may claim the other's security semantics.

New file `cli/modules/hornero_core/assistant_agents.v`. `hornero_core`
never prints/exits; every op returns `CommandResult`
(`cli/modules/hornero_core/result.v:ok_result`, per `cli/AGENTS.md`).

```v
pub struct AssistantAgent {
pub mut:
    id         string // stable slug, `^[a-z0-9][a-z0-9-]*$`, immutable after create
    name       string // display name, free text, redacted on output
    principal  string // MUST be in assistant_policy_principals (below)
    executable string // absolute path or empty = default Hermes pin
    home_ref   string // agent home id under XDG data, never a raw secret/path outside it
    workspace  string // AssistantWorkspace.id or empty = active workspace
    enabled    bool
}
```

Rules:

- Registry file: `assistant_agents_file()` = `assistant_dir()/agents.json`,
  mode 0600, outside the bwrap bind set (agent cannot rewrite its own
  identity), test override `HORNERO_ASSISTANT_AGENTS_FILE` — exactly the
  `assistant_workspaces_file()` pattern
  (`assistant_workspace.v:23`, `AssistantWorkspace` at `:14`).
- `principal` must validate against the fixed const
  `assistant_policy_principals` (`assistant_policy.v:55`: `javi.main`,
  `javi.subagent`, `javi.ask`, `javi.chat`, `javi.background`, `skill`,
  `plugin`, `mcp`). Free-form principals are DENY today
  (`assistant_policy_validate:188`, `assistant_policy_decide:215`); adding a
  principal means extending that const + validate + tests, never accepting
  arbitrary strings from the registry file. Corrupt/unknown-principal
  entries fail closed (report error, agent treated as disabled).
- Sessions gain an optional `agent` field on `AssistantSession`
  (`assistant.v:685`); the workspace-scoped continuity key
  (`assistant_session_continuity_key:789`) is unchanged, so existing
  single-agent sessions keep working.
- Broker: thread the chosen agent's principal through
  `assistant_broker_exec_report` instead of the hardcoded principal;
  catalogue stays `assistant_broker_catalogue`. No new tool surface.
- Open decision (blocks launch, not registry): per-agent sandbox homes.
  Today there is one `hornero-hermes.service` and one `~/.hermes` bound by
  `assistant_gateway_bwrap_argv`. Wave 1 must pick (a) one unit per agent
  (`hornero-hermes-<id>.service`, own home bind), or (b) shared gateway,
  registry only selects principal/workspace. Registry alone does not
  multi-home Hermes; do not claim isolation that (b) does not provide.

## 2. horneroctl agent command surface

Wiring only at `hornero_cli/assistant_options.v:parse_assistant` (leaf
allowlist), `hornero_cli/dispatch.v:run_assistant` (match arm),
`hornero_cli/help.v:command_help` (`assistant` + new `assistant agents`,
with `Examples:` per `cli/AGENTS.md`). Exit codes 0/1/2 unchanged.

| Command | Semantics |
|---|---|
| `assistant agents list [--json]` | Read-only. All entries, `enabled`, resolved principal/workspace, `is_default` flag. No paths containing secrets. |
| `assistant agents status [<id>] [--json]` | Read-only. Registry state + gateway state for that agent (`disabled\|not-installed\|installed-not-running\|running-incompatible\|running-compatible`, isolation `bubblewrap\|systemd-only`). |
| `assistant agents doctor [--json]` | Read-only checks: file perms 0600, JSON valid, principals valid, executable exists, workspace exists, unit/home consistency. Non-zero exit on any FAIL. Never fixes. |
| `assistant agents default [<id>] [--yes]` | No arg: report current default. With `<id>`: mutating, requires `--yes`; `--dry-run` previews. Default stored in registry file, not a separate defaults file. |
| `assistant agents launch [<id>] [--dry-run]` | Wave 1: **dry-run semantics only** — prints the exact unit name, bwrap argv shape, principal, workspace and home bind that *would* run, executes nothing. Real launch is gated on the §1 sandbox-home decision. |

General: `--dry-run` previews any external execution; mutating actions
also require `--yes` (`cli/AGENTS.md`). `launch` without `--dry-run`
returns a failed `CommandResult` (`not-implemented`, stable code) until
the home decision lands — never a silent no-op or fake success.

JSON contract fix (prerequisite for any UI binding): `CommandResult.data`
is `map[string]string` (`result.v:12-17`), so nested payloads are
stringified JSON. Wave 1 adds `schemaVersion` to assistant/agent payloads
and documents, per command, which `data.<key>` values are JSON strings.
Stable error codes required; no UI may bind to unversioned payloads.

## 3. Knowledge vault (extend, no new vault engine)

Extend `assistant_knowledge_markdown`/`assistant_knowledge_report`
(`assistant.v:267,301`), bound `assistant_knowledge_max_chars = 8000`
(`assistant.v:260`). Doc set, generated read-only on stdout:

1. CLI identity/version (`cli_version()` provenance + generated-at date).
2. Tool catalogue — reconcile to `assistant_broker_catalogue` /
   `assistant_broker_tools_report` (12 typed tools), not only the 7-tool
   `assistant_tools_report`; plus read-only `horneroctl catalogue` sections.
3. Policy summary (principals/actions, no rule secrets), workspace list,
   model/provider names (never keys).

Rules: provenance header on every document (generator, version, date,
source command); hard char bound with truncation marker; all content
through `redact_secrets` (`redact.v`); no secrets, no API keys, no absolute
developer paths, no file contents from outside the workspace scope.
A persisted vault file is optional and, if added, must follow the
`assistant_setup.v` ownership-receipt pattern
(`assistant_setup_write_owned_file`, preserve user-modified files) and
live outside sandbox binds. Do not import the Ryoku/Rashin static vault
(GPL-3.0, rejected in hornero#191) — concepts only, fresh MIT code.

## 4. Native vs extension decision

| Capability | Native (horneroctl/Hermes) | Extension (shell plugin) |
|---|---|---|
| Agent identity, ABAC principal, broker tools | Yes — only native code gets a principal | Never — plugins get no principal, no broker tools |
| Sandbox (bwrap+systemd), audit log, policy | Yes | Never marketed as sandboxed (QML runs as user UID) |
| ACP/MCP | Transport/principal (`mcp`, `mcp.invoke`), not a boundary | No ACP/MCP registration |
| Shell widgets (bar/dashboard/desktop QML), presentation | No | Yes — existing plugin contract only |

Confinement is bwrap + ABAC in horneroctl, per
`docs/javi-secure-harness.md`. ACP/MCP are not security boundaries.
Anything needing a tool, a principal, or isolation is native; anything
purely presentational is an extension. No third option in Wave 1.

## Tests (extend, do not duplicate)

`assistant_policy_test.v`, `assistant_workspace_test.v`,
`assistant_broker_test.v`, `assistant_contract_test.v`,
`assistant_gateway_test.v`, `assistant_test.v` (knowledge snapshot),
`assistant_setup_test.v` (markdown shape/bounds), and
`hornero_cli/assistant_dispatch_test.v` (help/parse/exit-code assertions,
dry-run proves non-execution with a nonexistent binary).
