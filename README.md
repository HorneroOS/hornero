# hornero

HorneroOS is an Arch-based operating-system project with a composable
product model. HorneroOS Desktop is a Wayland-first desktop powered by
Hornero Shell; Hyprland is its current validated compositor backend, not the
identity of the operating system. One edition catalogue defines the shared
base, desktop compositor choices, and planned server, agent-host, and creative
workstation compositions with explicit maturity.

This repository defines **HorneroOS as a composed product**: which components
make up the operating system, how editions combine package sets and what gets
released.

## What lives here

- Which components compose Hornero OS.
- Release manifests.
- Release composition and profile metadata.
- Integration between the HorneroOS repositories.
- Top-level build, test and release orchestration.

## What does NOT live here

This is intentionally **not a monorepo**. Implementation belongs in the
repository that owns it:

| Concern | Repository |
|---|---|
| Desktop shell / Quickshell UX | [HorneroOS/shell](https://github.com/HorneroOS/shell) |
| System CLI (`horneroctl`) | this repo, [`cli/`](cli/) |
| Reusable desktop/system defaults | [HorneroOS/config](https://github.com/HorneroOS/config) |
| Installation workflow/application | [HorneroOS/installer](https://github.com/HorneroOS/installer) |
| Technical/user documentation | [HorneroOS/docs](https://github.com/HorneroOS/docs) |
| Product website | [HorneroOS/website](https://github.com/HorneroOS/website) |
| Organization-wide community files | [HorneroOS/.github](https://github.com/HorneroOS/.github) |

## Layout

- `cli/` — the `horneroctl` system CLI implementation.
- `docs/` — locked CLI architecture, release process, and plans.
- `manifests/` — release manifests pinning component versions.
- `profiles/` — frozen-release component profiles.
- `editions/catalogue.yaml` — canonical Base/Desktop/Server/Agents/Studio
  package composition, compositor options, and maturity labels.
- `releases/` — release definitions and checklists.
- `scripts/` — top-level orchestration helpers.
- `tests/` — composition tests for the checker and manifests.

## Status

Composition is live: `horneroctl` builds from `cli/`, release manifests pin
the shell/config sources, and `scripts/compose.sh` materializes and validates
the pinned composition. The edition catalogue resolves four products from a
shared base and role package sets. Desktop remains in Preview; Hyprland is
supported and Niri is experimental. Server, Agents and Studio are planned,
not installable editions yet. Package resolution alone does not claim that an
edition is bootable or validated, and this repository does not produce images.

## License

[MIT](LICENSE).
