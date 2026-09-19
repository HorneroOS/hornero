# horneroctl

`horneroctl` is the Hornero OS system CLI: one non-interactive, agent-friendly
entry point for shell integration, appearance, configuration and health
checks. It is written in [V](https://vlang.io/) and modeled on the
`agent-toolkit` V CLI architecture (thin `cmd/` entry, `hornero_core` domain
modules returning `CommandResult`, `hornero_cli` adapter for
dispatch/render/help).

## Design rules (cli-for-agents)

- Non-interactive first: every input is a flag or positional; never prompts.
- Layered help: `horneroctl`, then `horneroctl <cmd> --help`. Every help text
  carries copy-pasteable **Examples**.
- `--json` / `--quiet` globals; `--dry-run` previews mutations; mutating
  actions additionally require `--yes`.
- Exit codes: `0` ok · `1` user/env/external error or unknown command ·
  `2` flag/usage error.
- Idempotent reads; destructive paths refuse without `--yes`.

## Commands

```text
horneroctl version [--json]
horneroctl doctor [--json]
horneroctl shell status
horneroctl shell ipc [--dry-run] -- <qs-args...>
horneroctl shell preset <list [--full]|current|apply <name>> [--dry-run|--yes]
horneroctl appearance status
horneroctl appearance sync [--dry-run|--yes]
horneroctl appearance call [--dry-run] -- <backend-args...>
horneroctl appearance theme <list|show <id>|get|apply <id> [--wallpaper <path>]|set <hornero-dark|hornero-light|pampa>> [--dry-run|--yes]
horneroctl appearance scheme <status|set-mode <dark|light>|set-variant <name>> [--dry-run|--yes]
horneroctl scheme ...                       # alias of appearance scheme
horneroctl config <paths|validate|show [key]>
horneroctl config snapshot <create|list|restore <id>> [--dry-run|--yes]
horneroctl config default-apps list [--dry-run]
horneroctl config materialize --dest <dir> [--dry-run|--yes]
horneroctl config gui [--pane <name>] [--dry-run]
horneroctl config migrate [--dry-run|--yes] [--helper PATH]
horneroctl package <check|updates> [--dry-run]
horneroctl backup <list|schedule>
horneroctl completion <bash|zsh|fish>
```

Delegation (no reinvention): shell IPC passes through to `qs`
(`HORNERO_QS_BIN` override); appearance status/sync delegate to the
HorneroOS/config backend (`HORNERO_APPEARANCE_BIN` override,
default `~/.local/bin/dots-gtk-theme`); theme apply and scheme setters
delegate to `dots-appearance` (`HORNERO_DOTS_APPEARANCE_BIN` override,
default `~/.local/bin/dots-appearance`); theme list/show read the
installed `theme.json` packs (`HORNERO_THEMES_DIR` override, else XDG
data `dots/themes`); theme get matches the live `dots-appearance
status --json` state against the official hornero-dark/hornero-light/pampa
trio (GTK discriminates the two dark-mode packs); theme set switches that
trio atomically (validate, resolve via the
packs, apply via `dots-appearance theme apply`, verify GTK/scheme agree,
best-effort rollback to the previous official theme); scheme status
reads the materialized scheme files under XDG state/cache; preset list/current read the installed presets
(`HORNERO_PRESETS_DIR` override, else XDG data `dots/shell-presets`)
and the state pointer; config show reads the materialized
`$XDG_CONFIG_HOME/hornero/shell.json` (system default as fallback);
snapshot list reads the materialized snapshots (`HORNERO_SNAPSHOTS_DIR`
override, else XDG cache `dots/snapshots`) while create/restore delegate
to `dots-config-manager` (`HORNERO_CONFIG_MANAGER_BIN` override,
default `~/.local/bin/dots-config-manager`); package check/updates
delegate to `dots-checkupdates`/`checkupdates`
(`HORNERO_CHECKUPDATES_BIN` override, read-only, unprivileged);
backup list reads the materialized `*.zip` archives
(`HORNERO_BACKUP_DIR` override, else `~/.dotfiles/backup`); backup
schedule prints the cron/systemd recipe and never installs it;
default-apps list delegates to `dots-default-apps --list`
(`HORNERO_DEFAULT_APPS_BIN` override, default
`~/.local/bin/dots-default-apps`, read-only); materialize delegates
to the config repo `materialize.sh --dest <dir>`
(`HORNERO_MATERIALIZE_BIN` override; `--dest` travels verbatim,
never rewritten to a legacy `dots/*` path); gui delegates to
`dots-settings-gui [--pane=<name>]` (`HORNERO_SETTINGS_GUI_BIN`
override, default `~/.local/bin/dots-settings-gui`); migrate delegates
to the config repo `migrate-to-hornero.sh [--dry-run]`
(`HORNERO_MIGRATE_BIN` override, or `--helper PATH` for one invocation;
needs `--yes`, copy-if-absent over the Hornero-owned rows only: themes,
presets, the preset pointer, scheme.json plus scheme state, the wallpaper
pointer, and notifs). The backend reports one `ROW <domain> <status>`
line per row (`<domain>: <status>` accepted too); `--json` carries them
as `row.<domain>` entries plus a `rows` count. `default-apps
set` stays out: `dots-default-apps --set` binds no arguments upstream
and handlr stays internal.

## Version report

`horneroctl version [--json]` prints the CLI version plus release
provenance: `shell`/`config` SHAs, manifest, and release name. The four
provenance values are baked in at build time as V comptime defines
(`hx_shell_sha`, `hx_config_sha`, `hx_manifest`, `hx_release`, each
defaulting to `unknown` so no `.git` checkout is needed at runtime).
`make.vsh build-cli` maps them from the `HX_SHELL_SHA`,
`HX_CONFIG_SHA`, `HX_MANIFEST`, and `HX_RELEASE` environment values;
`scripts/compose.sh` exports the shell/config pins (and manifest/release
names) when it builds the composed binary.

## Secrets redaction (doctor)

`doctor` echoes environment-derived text, so every check detail passes
through `hornero_core.redact_secrets` before display (human and `--json`
alike): `KEY=VALUE` / `KEY: VALUE` pairs whose key looks credential-like
(token, secret, password, key, auth, ...) render as `KEY=[redacted]`.
`env` probes additionally report only `KEY is set`, never values.
Contract: `docs/cli-architecture.md` section 4.

## Build / test

Requires V (latest master — run `v up` to update):

```sh
./make.vsh build-cli   # build/horneroctl
./make.vsh test        # unit tests (both modules)
./make.vsh fmt-check   # formatting gate (CI)
./make.vsh vet
./make.vsh install-cli # ~/.local/bin (override with --prefix=DIR)
```

## Layout

```text
cli/
├── cmd/horneroctl/main.v      # thin entry: dispatch(os.args) -> exit code
├── modules/hornero_core/      # domain logic, never prints
│   ├── errors.v               # ErrorClass taxonomy + exit codes
│   ├── result.v               # CommandResult + RenderMode
│   ├── paths.v                # XDG path contract
│   ├── execx.v                # dry-run-aware external runner
│   ├── version.v doctor.v shell_ipc.v appearance.v configx.v
│   ├── snapshots.v packages.v backups.v config_ops.v
│   ├── themes.v scheme.v theme_switch.v
│   └── core_test.v batch1_test.v batch2_test.v migrate_test.v
│       theme_switch_test.v
├── modules/hornero_cli/       # adapter: dispatch/options/render/help
│   ├── dispatch.v options.v help.v render.v batch1_options.v
│   ├── batch2_options.v migrate_options.v
│   └── dispatch_test.v batch1_dispatch_test.v batch2_dispatch_test.v
│       migrate_dispatch_test.v theme_switch_dispatch_test.v
├── make.vsh
├── README.md AGENTS.md
```

## Status

v0.1: framework + version/doctor/shell/appearance/config/completion.
v0.2 (phase 2, backend-grounded): appearance theme list/show/apply,
appearance scheme status/set-mode/set-variant (+ `scheme` alias),
config show values, shell preset list/current.
v0.3 (batch 1, backend-grounded): config snapshot create/list/restore
(list native, create/restore via `dots-config-manager`), package
check/updates (via `dots-checkupdates`/`checkupdates`, read-only),
backup list (native) + backup schedule (recipe only, never installed).
v0.4 (batch 2, backend-grounded): config default-apps list (via
`dots-default-apps --list`, read-only), config materialize --dest
(via the config repo `materialize.sh`, needs --yes), config gui
(via `dots-settings-gui`, launcher semantics). `default-apps set`
stays deferred: no verified upstream verb.
v0.5 (preview 1, worker D): config migrate (via the config repo
`migrate-to-hornero.sh`, copy-if-absent, needs --yes, per-row `--json`),
version release report (`shell`/`config` SHAs, manifest, release via
`HX_*` env at build time), doctor legacy-paths section (detected
`dots/*` state per contract row plus the migrate hint).
v0.6 (phase 2 appearance, this change): `appearance theme get`
(live backend state matched to the hornero-dark/hornero-light/pampa trio, read-only)
and `appearance theme set` (atomic official switch: validate, resolve,
apply via `dots-appearance theme apply`, verify GTK/scheme agree with
best-effort rollback; needs --yes, --dry-run previews).
The broader command surface is tracked in `../docs/cli-architecture.md`
(HorneroOS/hornero#1); appearance verbs stay a thin delegation layer until
native backends land (HorneroOS/shell#2).

## Out of scope

`device ...` (brightness/monitors/hardware: no pinned IPC path yet),
the `system` group (session/media/host utilities: no pinned backend yet),
and `setup` (namespace reserved for HorneroOS/installer flows; nothing
here may claim names under it) are explicitly out of scope for this CLI
until their owning backends land. Deferred siblings of shipped commands
fail with a usage error naming the missing backend instead of inventing
behavior.

## Roadmap (later phases, no verified backend yet)

- `shell config` (needs a pinned merge backend).
- Backup cron install (interactive by design).
- The dots-default-apps gui/info/type modes (interactive).
See `../docs/cli-architecture.md` section 7.

## License

MIT (see repository root `LICENSE`).
