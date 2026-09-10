# Theme and wallpaper split readiness plan

Status: planning only. This document audits split-readiness and
defines future repository boundaries. It creates no new repositories
and moves no implementation files.

Scope: `HorneroOS/config` theme recipes at
`profiles/themes/*/theme.json` (12 packs) plus
`profiles/themes/wallpapers.manifest.json`, tracked for
`HorneroOS/hornero` issue 2.

## Audited revisions

- `hornero@02f3dac` (composition scaffolding; this plan is a new
  file, no existing file edited).
- `config@6d47eee` (audited source of the 12 packs and the manifest).
- `dotfiles@b26db04` read-only reference (provenance recorded in the
  config manifest and `docs/DECISIONS.md`; never modified or pushed).

Full SHAs: `02f3daca6fa8608d42aa946adc81dd5d86ff41d0`,
`6d47eee746e6dc21eaf7bd5ba6a31afa58e0bdf8`,
`b26db04474d9e3ca4d78e4cc7e0e8bee40fbf5d3`.

All 12 `theme.json` files in config are byte-identical to the
dotfiles source at that revision.

## Method and checker

Run the integrity checker shipped with this plan:

```bash
docs/check-theme-refs.sh --config-root /path/to/config
docs/check-theme-refs.sh --config-root /path/to/config \
  --wallpapers-root /path/to/wallpapers
docs/check-theme-refs.sh --config-root /path/to/config \
  --wallpapers-root /path/to/wallpapers --strict
```

The checker verifies JSON validity, required keys
(`schemaVersion`, `id`, `name`, `defaultWallpaper`, `wallpaperDir`),
the `id == directory name` invariant, manifest-to-pack parity for
`defaultWallpaper` and `wallpaperDir`, unique ids, sane wallpaper
extensions, and absence of absolute paths or template markers.
Binary existence is advisory by default because config vendors
recipes only; `--strict` promotes dangling defaults to failures.

Observed result on the audited revision:

```text
CHECK-PASS: manifest is valid JSON
CHECK-PASS: 12 theme packs agree with manifest
check-theme-refs: ALL GREEN (warnings listed above, if any)
```

With `--wallpapers-root` pointed at the dotfiles wallpaper tree,
7 of 12 defaults resolve and 5 report dangling-default warnings
(see the audit list). With `--strict` that state exits 1 by design.

## Audit summary

- Recipes are self-contained: no binaries, no absolute paths, no
  chezmoi markers, no identity. Every pack carries `id`,
  `wallpaperDir`, and `defaultWallpaper`; `id == directory` holds
  12 of 12; manifest parity holds 12 of 12.
- Recipes are tiny: 12 packs total 5,102 bytes plus a 1,894 byte
  manifest (6,996 bytes combined). Each pack is 398 to 467 bytes.
- Binaries are external by design: config ships zero wallpaper
  images. Upstream dotfiles holds 54 images plus one README across
  8 directories (about 46 MB). Previews (`preview.jpg` per theme,
  about 382 KB total) exist in dotfiles but were intentionally not
  carried into config.
- Licensing is the main split blocker. Recipes inherit the MIT
  license of both repositories, but packs carry no per-asset license
  field and the wallpaper binaries carry no license metadata at
  all. Several upstream filenames point at third-party sources.
  Nothing may move into public `themes` or `wallpapers` repositories
  until each binary has a recorded license or is replaced.
- References point outward. Every pack names a GTK theme and an icon
  theme (system package names, not vendored files) and a wallpaper
  directory plus default file (fetched separately). Consumers resolve
  them through environment overrides with install-tree fallbacks,
  which is the seam the split must preserve.

## Per-pack audit

Format: size, default wallpaper ref, upstream status, GTK and icon
refs, license state, split note.

- `catppuccin-latte` (462 B): default
  `catppuccin-latte/catppuccin-latte-01.png`, dangling with no
  upstream directory. GTK Orchis-Light-Compact, icons Papirus.
  Recipe MIT, binary missing. `colorOnly` is true.
- `catppuccin-mocha` (467 B): default
  `catppuccin-mocha/catppuccin-mauve-02.png`, dangling with no
  upstream directory. GTK Orchis-Light-Compact, icons Papirus-Dark.
  Recipe MIT, binary missing. `colorOnly` is true.
- `everforest` (441 B): default
  `everforest/everforest-deep-01.png`, dangling with no upstream
  directory. GTK Orchis-Light-Compact, icons Numix-Circle. Recipe
  MIT, binary missing. `colorOnly` is true.
- `gruvbox` (406 B): default `gruvbox/gruvbox-anime-01.jpg`,
  resolves upstream. GTK Orchis-Light-Compact, icons Numix-Circle.
  Recipe MIT, binary unlicensed. Ready except binary license.
- `landscape` (405 B): default `landscape/landscape-01.jpg`,
  resolves upstream. GTK Orchis-Light-Compact, icons Numix-Circle.
  Recipe MIT, binary unlicensed. Ready except binary license.
- `monochrome` (402 B): default `monochrome/mono-curated-1.jpg`,
  resolves upstream. GTK Adwaita-dark, icons Papirus-Dark. Recipe
  MIT, binary unlicensed. Only Adwaita GTK ref in the set.
- `neon-city` (398 B): default `neon-city/neon-city-01.jpg`,
  resolves upstream. GTK Orchis-Light-Compact, icons Numix-Circle.
  Recipe MIT, binary unlicensed. Ready except binary license.
- `nord-dreams` (442 B): default
  `nord-dreams/nord-aurora-01.png`, dangling with no upstream
  directory. GTK Orchis-Light-Compact, icons Numix-Circle. Recipe
  MIT, binary missing. `colorOnly` is true.
- `rose-pine` (433 B): default
  `rose-pine/rose-pine-dawn-01.png`, dangling with no upstream
  directory. GTK Orchis-Light-Compact, icons Numix-Circle. Recipe
  MIT, binary missing. `colorOnly` is true.
- `soft-morning` (409 B): default
  `soft-morning/morning-lake-2.jpg`, resolves upstream. GTK
  Orchis-Light-Compact, icons Numix-Circle. Recipe MIT, binary
  unlicensed. Ready except binary license.
- `vapor-dreams` (423 B): default
  `vapor-dreams/vapor-dreams-01.jpg`, resolves upstream. GTK
  Orchis-Light-Compact, icons Numix-Circle. Recipe MIT, binary
  unlicensed. Ready except binary license.
- `warm-sunset` (414 B): default `warm-sunset/warm-sunset-05.jpg`,
  resolves upstream. GTK Orchis-Light-Compact, icons Numix-Circle.
  Recipe MIT, binary unlicensed. Ready except binary license.

Supporting counts: upstream wallpaper binaries per directory are
`curated` 7, `gruvbox` 13, `landscape` 5, `monochrome` 2,
`neon-city` 6, `soft-morning` 6, `vapor-dreams` 7, `warm-sunset` 8.
There is no upstream directory for the five `colorOnly` packs, so
`dots_apply_theme` cannot succeed for them from a clean materialize
today: wallpaper resolution is mandatory even for color palettes.

## Reference surface consumers depend on

- `DOTS_THEMES_DIR` (default `~/.local/share/dots/themes`): read by
  `apply-appearance.sh`, `list-themes.py`, `gtk-theme-manager.sh`,
  and `snappy-switcher-manager.sh`.
- `DOTS_WALLPAPERS_DIR` (default `~/.local/share/dots/wallpapers`)
  and `DOTS_PICTURES_WALLPAPERS` (default `~/Pictures/Wallpapers`):
  resolution order is Pictures first, then data dir, then first
  image in the directory.
- `profiles/base/profile.toml` `[modules.themes]` maps
  `profiles/themes` to `{data}/dots/themes`.
- `scripts/materialize.sh` installs `profiles/themes` to
  `$DATA_HOME/dots/themes`; `tests/test_materialize.sh` asserts
  exactly 12 packs materialize.

Any split must keep these variable names and fallback order stable,
or migrate all four consumers together.

## Future repository boundaries

Do not create these repositories yet. When an independent lifecycle
is justified, the intended homes are:

- `HorneroOS/themes`: versioned theme recipes. Owns pack schema,
  per-pack metadata, previews, and the recipe test matrix. Never
  owns wallpaper binaries.
- `HorneroOS/wallpapers`: versioned wallpaper binaries. Owns
  per-directory packs, the wallpaper manifest, checksums, and
  per-asset licensing. Never owns color or GTK semantics.
- Icons: no dedicated repository yet. Icon themes are bare package
  names today (`Numix-Circle` 9 packs, `Papirus-Dark` 2 packs,
  `Papirus` 1 pack). Record them as package dependencies of the
  config profile. A future icons repository is only justified if
  Hornero starts shipping its own icon files; that decision is
  explicitly out of scope here.

## Exact file-move mapping

No file moves in this change. The mapping below is the execution
order for the future split, when approved:

- `config:profiles/themes/<id>/theme.json` (12 files) move to
  `themes:packs/<id>/theme.json`. Keep ids and filenames stable.
- Dotfiles-only `themes/<id>/preview.jpg` (12 files) move to
  `themes:packs/<id>/preview.jpg`. Re-add only with a cleared
  license for each image.
- `config:profiles/themes/wallpapers.manifest.json` moves to
  `wallpapers:wallpapers.manifest.json`. The canonical copy lives
  with the binaries.
- Optionally pin `wallpapers.manifest.json` from the wallpapers
  release into `themes:wallpapers.manifest.pin.json` as a version
  pointer, never as a fork.
- Dotfiles `wallpapers/<dir>/*` image files (54 files) move to
  `wallpapers:packs/<dir>/`. One directory per `wallpaperDir` plus
  the `curated` pool.
- Dotfiles `wallpapers/README.md` is rewritten as
  `wallpapers:README.md` documenting pack layout and licenses.
- `config:lib/dots/list-themes.py` stays in config; the themes
  repository mirrors its fixture expectations. The contract owner
  stays with the consumer.
- `config:lib/dots/wallpaper-resolver.sh` stays in config.
  Resolution order is a config contract.
- `config:lib/dots/apply-appearance.sh` stays in config and keeps
  following the environment variables above.
- `config:profiles/base/profile.toml` `[modules.themes]` stays in
  config and gains one source stanza per split repository.
- `config:scripts/materialize.sh` and `tests/test_materialize.sh`
  stay in config and learn a second fetch step. No behavior change
  until the split lands.

## Extraction checklist

1. Clear wallpaper licensing: record a license per binary or
   replace uncleared files. Block the wallpapers repository until
   this is done.
2. Resolve the five dangling defaults (`catppuccin-latte`,
   `catppuccin-mocha`, `everforest`, `nord-dreams`, `rose-pine`):
   ship a matching binary per `wallpaperDir`, or point the pack at
   an existing licensed file. Re-run the checker with `--strict`
   until green.
3. Freeze the pack schema (`schemaVersion`, required keys,
   `id == dir`, allowed extensions) and publish it from the future
   themes repository.
4. Decide the preview policy (ship `preview.jpg` per pack or
   generate at build time) after confirming preview licenses.
5. Create the wallpapers repository with `packs/<dir>/`,
   checksums, and the canonical `wallpapers.manifest.json`.
6. Create the themes repository with `packs/<id>/theme.json`,
   previews, and a manifest pin pointing at a wallpapers release.
7. Teach the config fetch step to pull both releases into
   `DOTS_THEMES_DIR` and `DOTS_WALLPAPERS_DIR`; keep the
   Pictures-first resolution order unchanged.
8. Update `profiles/base/profile.toml` to declare the two new
   sources and extend `tests/test_materialize.sh` to assert both
   trees materialize.
9. Run `scripts/validate.sh`, `tests/test_materialize.sh`,
   `scripts/guard-personal-data.sh`,
   `docs/check-theme-refs.sh --strict`, and markdownlint before
   merging the split.

## Split-friendly adjustments considered, not applied

No config or code change ships with this plan: the hornero change
is two new files only, so behavior is unchanged by construction.
The following candidates were evaluated and deliberately left as
future steps because each would alter shipped behavior or schema
and belongs in its owning repository with its own review:

- Add a per-pack `license` field and a per-asset license table to
  the manifest. Schema addition; do it in the themes and
  wallpapers repositories, not as a drive-by here.
- Normalize the inconsistent `colorOnly` key (present in 5 packs,
  absent in 7) and the `gtkPreferDark` versus `gtkColorScheme`
  derivation. Consumer-visible semantics; needs a consumer
  migration, not a silent fix.
- Replace the five dangling `defaultWallpaper` values. Data fix
  with visible behavior change; blocked on licensing anyway.
- Pin GTK and icon theme package versions instead of bare names.
  Turns implicit system dependencies into explicit ones; belongs
  with the profile, not the plan.
- Add `$schema` pointers or a JSON schema file. New contract;
  publish it from the future themes repository.

## Risks and blockers

- Wallpaper redistribution rights are unknown; this alone blocks
  any public wallpapers repository.
- Five packs cannot apply from a clean install today because
  wallpaper resolution is mandatory. The split must not enshrine
  dangling refs.
- GTK and icon themes are external system packages with no version
  pins; a theme can break without any Hornero change.
- Previews were dropped from config to keep it small; whichever
  future repository re-adds them inherits the same license audit.

## Verification evidence

- `check-theme-refs.sh --config-root <config@6d47eee>`:
  manifest valid, 12 packs agree with manifest, exit 0.
- Same checker with `--wallpapers-root` at the dotfiles wallpaper
  tree: 7 defaults resolve, 5 dangling warnings for the
  `colorOnly` packs.
- `shellcheck -S error docs/check-theme-refs.sh`: pass.
- `markdownlint docs/theme-split-plan.md`: clean.
- Personal-data rescan before push: no names, emails, hosts,
  SSIDs, or tokens in the two new files (recipes, SHAs, and
  package names only).
