# AGENTS.md — horneroctl (V CLI)

## Architecture

- `hornero_core` = pure domain logic. It MUST NEVER print, read argv, or call
  `exit()`. Every command returns `CommandResult`; every failure path returns
  `DomainError` (or a failed `CommandResult` for command-level failures).
- `hornero_cli` = adapter. `dispatch(args []string) int` is the only entry;
  it never calls `exit()` so tests can assert exit codes directly.
- `cmd/horneroctl/main.v` stays thin: `dispatch(os.args)` → `exit(code)`.

## CLI contract (non-negotiable)

- Non-interactive: flags/positionals only, no prompts, no menus.
- Every subcommand owns `--help` with an `Examples:` section; add a
  dispatch test asserting it stays present.
- Exit codes: `0` ok · `1` user/env/external/unknown-command ·
  `2` unknown-flag/usage. Unknown flags must print a correct example.
- `--json` / `--quiet` work on every command. `--dry-run` previews any
  external execution; mutating actions ALSO require `--yes`.
- Never shell out with interpolated user input unsanitized; `execx.v`
  `command_line()` quotes args.

## V specifics

- Pinned toolchain: `.v-version`. Keep code conservative (must compile on the
  pin AND reasonably newer V).
- `VMODULES` points at `cli/modules` (see `make.vsh`); never use relative
  imports.
- `v fmt -w` before commit; `fmt-check`, `vet`, `test` must all pass.
  Canonical formatter is the CI toolchain (prebuilt weekly from `.v-version`,
  runnable locally via `V=<path-to-weekly-v>`); on formatter drift, CI wins.
- Completions/help strings containing `$` MUST escape as `\$` (V
  interpolates `${}`/`$ident` in strings).
- JSON via `x.json2` (`encode(v, escape_unicode: true)`,
  `decode[T](s)`); std `json` is deprecated upstream — do not use it.

## Testing

- `*_test.v` next to code; `v test modules/<name>`.
- Assert exit codes via `dispatch([...])`, never via shell exit codes.
- Dry-run tests must prove non-execution (nonexistent binary + `dry_run: true`
  → ok).
- No network, no compositor, no HOME mutation in unit tests (override XDG
  env vars when paths are involved; unset afterwards).

## Provenance

- Fresh MIT implementation. Attribute `agent-toolkit` V-CLI patterns in
  `cli/README.md`; do not copy its code verbatim.
- No personal data, no secrets, no absolute developer paths — ever.
