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
horneroctl appearance status
horneroctl appearance sync [--dry-run|--yes]
horneroctl appearance call [--dry-run] -- <backend-args...>
horneroctl config <paths|validate|show>
horneroctl completion <bash|zsh|fish>
```

Delegation (no reinvention): shell IPC passes through to `qs`
(`HORNERO_QS_BIN` override); appearance delegates to the
HorneroOS/config backend (`HORNERO_APPEARANCE_BIN` override,
default `~/.local/bin/dots-gtk-theme`); config reads the XDG contract
(`$XDG_CONFIG_HOME/hornero/shell.json`).

## Build / test

Requires V (see `.v-version`):

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
│   └── core_test.v
├── modules/hornero_cli/       # adapter: dispatch/options/render/help
│   └── dispatch_test.v
├── make.vsh .v-version
├── README.md AGENTS.md
```

## Status

v0.1: framework + version/doctor/shell/appearance/config/completion.
The broader command surface is tracked in `../docs/cli-architecture.md`
(HorneroOS/hornero#1); appearance verbs stay a thin delegation layer until
native backends land (HorneroOS/shell#2).

## License

MIT (see repository root `LICENSE`).
