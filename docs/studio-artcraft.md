# ArtCraft Launcher — Studio experimental opt-in

Status: `experimental`. A single, optional Studio application
(`artcraft-launcher`) that a user selects explicitly. It is never
installed by specialization or group selection, and nothing in this
repository installs it automatically.

## What it is

[ArtCraft Launcher](https://github.com/storytold/craft-launcher) installs
and updates the Craft applications. The catalogue of Craft applications
is managed by the launcher itself and can change without a HorneroOS
update, so this repository never hardcodes its contents. The launcher
is early-alpha software; expect upstream changes and report crashes to
the upstream project.

## Verified upstream pin

- Release: `v0.19.0` (a deliberate pin, not a claim that it is latest).
- Package: `ai.storyteller.artcraft-launcher` (upstream desktop ID).
- Assets: signed `.pkg.tar.zst` (`.sig`), AppImage (`.asc`),
  `SHA256SUMS.txt` (`.asc`) and `release-signing-key.asc`.
- Release signing key fingerprint (pin this out-of-band; the key ships
  with the release it signs, so fetching it from the same release alone
  is circular trust):

  `2B76741B414AAD6CD33E631213A005C0B9D7C3ED`

Signatures on the pinned release were verified against this key and
the SHA256 sums matched when the pin was recorded. Re-verify both
before trusting any newer release.

## Install (manual, user-approved)

The selected channel is the signed vendor Arch package, installed
manually after explicit user approval. Calamares and `horneroctl`
never download or install it.

```bash
cd "$(mktemp -d)"
curl -LO https://github.com/storytold/craft-launcher/releases/download/v0.19.0/artcraft-launcher-0.19.0-linux-x86_64.pkg.tar.zst
curl -LO https://github.com/storytold/craft-launcher/releases/download/v0.19.0/artcraft-launcher-0.19.0-linux-x86_64.pkg.tar.zst.sig
curl -LO https://github.com/storytold/craft-launcher/releases/download/v0.19.0/SHA256SUMS.txt
curl -LO https://github.com/storytold/craft-launcher/releases/download/v0.19.0/release-signing-key.asc
gpg --import release-signing-key.asc
gpg --fingerprint # must show 2B76741B414AAD6CD33E631213A005C0B9D7C3ED
gpg --verify artcraft-launcher-0.19.0-linux-x86_64.pkg.tar.zst.sig
grep "artcraft-launcher-0.19.0-linux-x86_64.pkg.tar.zst$" SHA256SUMS.txt | sha256sum -c -
sudo pacman -U artcraft-launcher-0.19.0-linux-x86_64.pkg.tar.zst
```

A failed signature or checksum stops the install. The AppImage is a
fallback for users who prefer a user-local install in `~/Applications`;
it needs working FUSE or `APPIMAGE_EXTRACT_AND_RUN=1`.

## Lifecycle

- Record intent: `horneroctl studio selection set --application artcraft-launcher`
  (records only; installs nothing).
- State: `horneroctl studio app show artcraft-launcher --json` reports
  desktop-file presence and selection; version and update state are
  reported by the launcher itself (`unknown` here).
- Updates: the launcher self-updates and updates its Craft applications
  outside pacman. HorneroOS neither pins nor rolls back those updates;
  check for drift by comparing the installed state with this pin.
- Uninstall: remove applications from inside the launcher first, then
  `sudo pacman -R ai.storyteller.artcraft-launcher`, and remove any
  leftover `~/Applications` AppImage copy and launcher-managed files.
  Removing the Studio selection never uninstalls anything by itself.

## Prerequisites and limits

Native Wayland needs `xdg-desktop-portal` and
`xdg-desktop-portal-hyprland` (plus `xdg-desktop-portal-gtk` for the
file chooser). Formal HorneroOS acceptance on a Studio Preview ISO is
tracked in HorneroOS/qa#36 and stays pending until real VM evidence
exists; this document is not a support claim.

## Trademark

ArtCraft, the ArtCraft name and the A mark are trademarks of the
ArtCraft Team. They are not licensed under MIT or Apache-2.0 and are
used here only unmodified, as part of the unmodified launcher. Code is
`MIT OR Apache-2.0` per the upstream package metadata.
