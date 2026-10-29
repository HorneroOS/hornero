# ArtCraft Launcher (AppImage, manual) — Studio reference-only

Status: `reference-only`. Not installed from the catalogue, not on the ISO.
Model: same as `penpot` in `editions/catalogue.yaml`. Promotion path:
[HorneroOS/hornero#325](https://github.com/HorneroOS/hornero/issues/325).

## Why manual AppImage for this step

Three channels were compared (#325 owns the promotion decision):

| Channel | What it is | Verdict for step 1 |
| --- | --- | --- |
| AUR `artcraft-launcher-appimage` | Thin wrapper around the official AppImage (download + `chmod +x` + `.desktop`) from a brand-new maintainer | Rejected: extra trust hop, zero reproducibility gain over a verified direct download |
| Manual AppImage (chosen) | Official `artcraft-launcher-*-linux-{x86_64,aarch64}.AppImage` from GitHub releases, SHA256-verified, user-local in `~/Applications` | Chosen: no root, no build, matches the flow the team already smoke-tested |
| Vendor `.pkg.tar.zst` | Official pacman-compatible tarball per release (x86_64 + aarch64) | Leading candidate for #325: pacman-trackable, but installs to `/usr` (needs root) and stays a prebuilt binary outside any repo |

Source: https://github.com/storytold/craft-launcher/releases
Pinned version: `0.8.1` (revalidate here when moving the pin; upstream
`getartcraft.com/apps` still linked 0.5.1 at check time).

Verified 2026-10-28 on CachyOS (Arch base, KVM kernel): 12 MB x86_64
AppImage, `SHA256SUMS.txt` OK, ELF x86-64 static type-2 runtime, `--help`
boots (log `ArtCraft Launcher 0.8.1`) and exits 0 headless. Normal mounting
needs working host FUSE (present there); otherwise `APPIMAGE_EXTRACT_AND_RUN=1`.
Real smoke test same day on Arch + Hyprland 0.56.2 (Wayland, both
xdg-desktop-portal backends active): native window, no log errors. This
validates the Arch + Hyprland + portal base (close to Hornero Desktop),
NOT Hornero Shell integration or the ISO — that needs a HorneroOS VM.

Evidence screenshots live in the PR description, kept out of the repo on
purpose: point-in-time smoke evidence, not versioned product assets.

## Manual install

```bash
mkdir -p ~/Applications && cd ~/Applications
ARCH=$(uname -m)  # x86_64 or aarch64, matching upstream asset names
curl -LO https://github.com/storytold/craft-launcher/releases/download/v0.8.1/artcraft-launcher-0.8.1-linux-${ARCH}.AppImage
curl -LO https://github.com/storytold/craft-launcher/releases/download/v0.8.1/SHA256SUMS.txt
grep "artcraft-launcher-0.8.1-linux-${ARCH}.AppImage$" SHA256SUMS.txt | sha256sum -c -
chmod +x artcraft-launcher-0.8.1-linux-${ARCH}.AppImage
./artcraft-launcher-0.8.1-linux-${ARCH}.AppImage
```

The `grep` pins verification to the downloaded file: a missing or
mismatched manifest entry fails instead of passing silently
(`--ignore-missing` would hide that case).

Wayland/Hyprland prerequisites (already on Desktop; if anything is missing):
`wayland, xdg-desktop-portal[-hyprland], mesa/vulkan-icd-loader, noto-fonts-cjk`
(CJK optional). The AppImage embeds a static runtime; normal mounting needs
working host FUSE, but not `libfuse2`. Without FUSE, use
`APPIMAGE_EXTRACT_AND_RUN=1`.

Craft apps install/update from inside the launcher, outside pacman: the
catalogue version is only valid at install time. Never replace a running app
(the launcher blocks it).

## How to test it

1. Composition (no VM):
   ```bash
   python3 scripts/resolve-edition.py studio --application artcraft-launcher
   # must fail with: reference-only and cannot be installed from the catalogue
   python3 -m pytest tests/test_studio_selection.py tests/test_editions.py tests/test_composition.py -q
   ```
2. Manual smoke on a HorneroOS Desktop/Studio Preview VM (Hyprland, then Niri):
   - AppImage runs, icon shows in the Hornero Shell launcher.
   - `desktop-file-validate` for the generated `.desktop` if integrated into the menu.
   - Open a file dialog (portal path), create a project, install/update a
     Craft app, take a screenshot.
   - Repeat on Niri (experimental): report only, non-blocking.
3. Evidence: screenshots + manual `run.json`-style record (ISO SHA, launcher
   version, compositor). No bundle PASS means no promotion to `support`.
   See `HorneroOS/qa:docs/STUDIO-ACCEPTANCE.md` (fail-closed gate).

## Promotion notes for #325

- Upstream marks the launcher and all 13 Craft apps early alpha / in
  development → must land as `experimental: true` (like Graphite), opt-in.
- Licensing is clean (MIT / Apache-2.0 → `licenseClass: open-source`); no
  proprietary opt-in machinery needed. Trademark limit: the ArtCraft name,
  logo and "A" mark are NOT open-licensed (upstream
  `docs/brand/LICENSE-brand.txt`) — the website must not derive assets
  from them.
- The launcher manages app lifecycle outside pacman (installs from upstream
  release packages, self-updates): the catalogue can only ever resolve the
  launcher, never the 13 app versions.
