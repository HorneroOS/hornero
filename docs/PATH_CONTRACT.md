# Hornero Runtime Path Contract

Canonical record of every runtime path the Hornero OS user session reads or
writes. This document DEFINES the contract; implementation fan-out happens
later. No shell, config, or horneroctl behavior was changed to write it.

Evidence was inspected in fresh clones at these upstream commits:

- `HorneroOS/shell` at `c6d1685`
- `HorneroOS/config` at `dc11c07`
- `HorneroOS/hornero` at `793c256`
- `ulises-jeremias/dotfiles` at `b26db04` (read-only legacy reference)

`horneroctl` outputs below were produced by building the `hornero` clone
(`cli/make.vsh build-cli`) and running `config paths`, `config show`, and
`config validate`.

## The rule

1. **New writes go to `hornero/*`.** Any code written after this contract
   persists user data, state, or cache under `$XDG_*_HOME/hornero/...`.
2. **Old reads keep a `dots/*` fallback where safe.** Existing installs hold
   data under `dots/*`; readers check the canonical `hornero/*` location
   first and fall back to the documented `dots/*` location. Fallbacks are
   read-only: nothing new is ever written to `dots/*`.
3. **Deprecation note.** The `dots/*` locations are legacy. They stay
   readable for one migration window so existing installs keep working.
   Removal of any fallback is a separate, announced decision, not part of
   this contract.

Two locations are already canonical today and have no fallback: `shell.json`
and the theme manifest (see rows 6 and 8).

## Canonical table

| # | Domain | Canonical path (new writes) | Documented `dots/*` fallback (reads only) | Owning repo + evidence |
| --- | --- | --- | --- | --- |
| 1 | Theme packs (installed `theme.json` recipes) | `$XDG_DATA_HOME/hornero/themes/<id>/theme.json` | `$XDG_DATA_HOME/dots/themes/<id>/theme.json` | hornero `cli/modules/hornero_core/themes.v:18` (`resolve_themes_dir`); shell `services/ThemePipeline.qml:12` (`themesDir`); config `scripts/materialize.sh:84` (installs `profiles/themes` to `$DATA_HOME/dots/themes`); config `lib/dots/list-themes.py:120` (`_data_home() / "dots/themes"`); config `bin/dots-appearance:11` (`THEMES_DIR` default) |
| 2 | Shell layout presets (catalogue `*.json`) | `$XDG_DATA_HOME/hornero/shell-presets/*.json` | `$XDG_DATA_HOME/dots/shell-presets/*.json` | hornero `cli/modules/hornero_core/presets.v:23` (`resolve_presets_dir`, override `HORNERO_PRESETS_DIR`); shell `CMakeLists.txt:81` (installs vendored `presets/`); shell `modules/layoutpicker/PresetGrid.qml:58` (lists via `dots-quickshell preset list`); dotfiles `home/dot_local/bin/executable_dots-quickshell:61` (`PRESETS_DIR`) |
| 3 | Active-preset pointer | `$XDG_STATE_HOME/hornero/current-shell-preset` | `$XDG_STATE_HOME/dots/current-shell-preset` | hornero `cli/modules/hornero_core/presets.v:37` (`resolve_preset_state_file`, override `HORNERO_PRESET_STATE_FILE`); dotfiles `home/dot_local/bin/executable_dots-quickshell:62` (`CURRENT_PRESET_FILE`) |
| 4 | Scheme runtime (`scheme.json`, source of truth for colours) | `$XDG_CACHE_HOME/hornero/smart-colors/scheme.json` | `$XDG_CACHE_HOME/dots/smart-colors/scheme.json` | hornero `cli/modules/hornero_core/scheme.v:44` (`color_scheme_file`); shell `services/ThemePipeline.qml:24` (`schemeJson`); shell `services/Colours.qml:95` (`schemeFileView`); config `lib/dots/apply-appearance.sh:10` (`DOTS_SCHEME_FILE`); dotfiles `home/dot_local/bin/executable_dots-color-scheme:15` (`SCHEME_FILE`) |
| 5 | Scheme state (`state.json`: mode/flavour/variant + `gtkColorScheme` policy; absent policy means `follow`) | `$XDG_STATE_HOME/hornero/scheme/state.json` | `$XDG_STATE_HOME/dots/scheme/state.json` | hornero `cli/modules/hornero_core/scheme.v:36` (`scheme_state_file`); config `lib/dots/gtk-theme-manager.sh:29` (`DOTS_SCHEME_STATE`); config `lib/dots/apply-appearance.sh:331` (wallpaper-only path reads `$DOTS_STATE_DIR/scheme/state.json`); dotfiles `home/dot_local/bin/executable_dots-color-scheme:16` (`STATE_DIR`/`STATE_FILE`); config `bin/dots-appearance:150` (hardcoded `$HOME/.local/state/dots/scheme/state.json`, must be fixed per checklist) |
| 6 | `shell.json` (single runtime settings file; user file first, system default as fallback) | `$XDG_CONFIG_HOME/hornero/shell.json` (user) + `/etc/xdg/hornero/shell.json` (system default). No `dots/*` fallback: already canonical. | none | hornero `cli/modules/hornero_core/paths.v:36` (`shell_config_file`) and `paths.v:41` (`system_shell_config_file`); hornero `cli/modules/hornero_core/configx.v:35` (user-first load order); shell `config/Config.qml:497` (`FileView` at `${Paths.config}/shell.json`); shell `utils/Paths.qml:19` (`config`); dotfiles `home/dot_local/bin/executable_dots-quickshell:60` (`SHELL_CONFIG`) |
| 7 | Snapshots (`config_<timestamp>/` + `metadata.json`) | `$XDG_CACHE_HOME/hornero/snapshots/config_*/` | `$XDG_CACHE_HOME/dots/snapshots/config_*/` | hornero `cli/modules/hornero_core/snapshots.v:20` (`resolve_snapshots_dir`, override `HORNERO_SNAPSHOTS_DIR`); dotfiles `home/dot_local/bin/executable_dots-config-manager:25` (`SNAPSHOTS_DIR="$HOME/.cache/dots/snapshots"`) |
| 8 | Theme manifest (wallpaper refs + fetch locations) | `$XDG_DATA_HOME/hornero/themes/wallpapers.manifest.json`. No fallback: already `hornero/*`-native. | none | hornero `cli/modules/hornero_core/configx.v:127` (`config_validate_report`); config `docs/DECISIONS.md:24` (manifest records refs, binaries not vendored) |
| 9 | Runtime state: wallpaper pointer (one-line file) | `$XDG_STATE_HOME/hornero/wallpaper/path` | `$XDG_STATE_HOME/dots/wallpaper/path` | shell `utils/Paths.qml:17` (`wallpaperPointer`, must match `wallpaper-resolver.sh`); config `lib/dots/wallpaper-resolver.sh:9` (`DOTS_STATE_DIR`); config `lib/dots/apply-appearance.sh:9` (`DOTS_WALLPAPER_POINTER_FILE`); dotfiles `home/dot_local/bin/executable_dots-color-scheme:18` (`CURRENT_WALL_CACHE`) |
| 10 | Runtime state: notifications (`notifs.json`) and image caches | `$XDG_STATE_HOME/hornero/notifs.json`; `$XDG_CACHE_HOME/hornero/imagecache[/notifs]` | `$XDG_STATE_HOME/dots/notifs.json`; `$XDG_CACHE_HOME/dots/imagecache[/notifs]` | shell `services/Notifs.qml:91` (`${Paths.state}/notifs.json`); shell `services/Notifs.qml:215` (`Paths.notifimagecache`); shell `components/images/CachingImage.qml:26` (`Paths.imagecache`); shell `utils/Paths.qml:21` (`imagecache`, `notifimagecache`) |
| 11 | Installed wallpapers (binary packs) | `$XDG_DATA_HOME/hornero/wallpapers/` (see open question 1) | `$XDG_DATA_HOME/dots/wallpapers/` | shell `services/ThemePipeline.qml:13` (`wallpapersDir`); config `lib/dots/apply-appearance.sh:6` (`DOTS_WALLPAPERS_DIR`); config `docs/DECISIONS.md:89` (binaries never vendored, shipped via release pipeline) |
| 12 | Shell library / helper binaries (read-only lookup, not migrated data) | `/usr/lib/hornero` with `$HOME/.local/lib/dots` + `$HOME/.local/bin` as legacy lookup | `$HOME/.local/lib/dots`, `$HOME/.local/bin/dots-*` | shell `utils/Paths.qml:25` (`libdir`); config `scripts/materialize.sh:72` (`lib/dots` to `$LIB_DIR`) and `materialize.sh:29` (`LIB_DIR="$DEST/.local/lib/dots"`) |

Base-directory resolution is `explicit env override -> XDG -> $HOME default`
everywhere: shell `utils/Paths.qml:14` (`data`, `state`, `cache`, `config`
with `DOTS_*_DIR` overrides), shell `docs/ARCHITECTURE.md:29`, hornero
`cli/modules/hornero_core/paths.v:26` (`resolve_paths`). Materializer
hermeticity: `config/scripts/materialize.sh:23` honors XDG only for real-`$HOME`
installs so `--dest` test installs never leak.

## Observed `horneroctl` outputs (binary built from `793c256`)

`horneroctl config paths`:

```text
user config:   /home/ulisesjcf/.config
user data:     /home/ulisesjcf/.local/share
user state:    /home/ulisesjcf/.local/state
user cache:    /home/ulisesjcf/.cache
system config: /etc/xdg
shell config:  /home/ulisesjcf/.config/hornero/shell.json
```

`horneroctl config show` summarizes the materialized `shell.json`
(top-level keys with object/array counts); `horneroctl config show <key>`
resolves one dot-notation key (`cli/modules/hornero_core/configx.v:88`).
`horneroctl config validate` reports `ok shell config: .../hornero/shell.json`
plus the optional theme manifest at `.../hornero/themes/wallpapers.manifest.json`
(`cli/modules/hornero_core/configx.v:113`); both commands read without writing.

## Contract-conformance checklist (for LATER workers, not implemented here)

- [ ] hornero: extend `resolve_themes_dir`, `resolve_presets_dir`,
  `resolve_preset_state_file`, `scheme_state_file`/`color_scheme_file`,
  `resolve_snapshots_dir`, and the wallpaper/notifs/cache path helpers with
  canonical-first + `dots/*`-fallback reads; all writes target `hornero/*`.
- [ ] shell: teach `utils/Paths.qml` the `hornero/*`-first resolution with
  `dots/*` fallback (keeping the `DOTS_*_DIR` env overrides); update
  `services/ThemePipeline.qml`, `services/Colours.qml`,
  `services/Notifs.qml`, `components/images/CachingImage.qml`,
  `config/Config.qml`, and `docs/ARCHITECTURE.md` accordingly.
- [ ] config: teach `lib/dots/*` (`apply-appearance.sh`,
  `wallpaper-resolver.sh`, `gtk-theme-manager.sh`, `list-themes.py`) and
  `bin/dots-appearance` (notably the hardcoded `$HOME` paths at
  `bin/dots-appearance:150`, `:268`-`:269`, `:279`) the same
  canonical-first reads; `scripts/materialize.sh` installs theme packs and
  presets to the canonical `hornero/*` destinations (with back-compat
  symlinks or a one-shot migrator, per open question 3).
- [ ] Migration tooling: ship the one-shot `dots/*` to `hornero/*`
  migrator (owner TBD, see open question 3) before any fallback is removed.
- [ ] Docs: record the fallback-removal decision and date once agreed; keep
  this file as the single source of truth for paths.

## Explicit-Open-Questions

1. Do installed wallpaper binaries move to
   `$XDG_DATA_HOME/hornero/wallpapers/`, or stay under `dots/wallpapers`
   because `wallpapers.manifest.json` already abstracts their location?
2. What is the migration window (date or release) for removing the `dots/*`
   read fallbacks?
3. Who owns the one-shot migrator (`dots/*` to `hornero/*`): `horneroctl`,
   `config/scripts/materialize.sh`, or install-time logic? (The installer
   repo is out of scope for this contract step.)
4. Symlink back-compat (`dots/*` symlinks pointing at `hornero/*`) versus
   dual-path reads: which strategy do shell/config adopt during the window?
5. Does `$XDG_CONFIG_HOME/quickshell` (hornero
   `cli/modules/hornero_core/paths.v:46`, dotfiles
   `executable_dots-quickshell:59`) stay as-is as a third-party namespace,
   or does any part of it move under `hornero/`?
6. `config validate` treats a missing user `shell.json` as "defaults apply"
   (not a failure) today (`configx.v:117`); does the contract want a
   stricter stance once the migrator exists?
