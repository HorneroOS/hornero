# hornero

Hornero OS is an Arch Linux-based desktop operating system built around
Wayland, Hyprland and Quickshell, with a distinctive Argentine-inspired
identity and a long-term focus on deeply integrated AI-native computing.

This repository defines **Hornero OS as a composed product**: which components
make up the distribution, how they fit together and what gets released.

## What lives here

- Which components compose Hornero OS.
- Release manifests.
- Distribution profiles and editions.
- Integration between the HorneroOS repositories.
- Top-level build, test and release orchestration.

## What does NOT live here

This is intentionally **not a monorepo**. Implementation belongs in the
repository that owns it:

| Concern | Repository |
|---|---|
| Desktop shell / Quickshell UX | [HorneroOS/shell](https://github.com/HorneroOS/shell) |
| Reusable desktop/system defaults | [HorneroOS/config](https://github.com/HorneroOS/config) |
| Installation workflow/application | [HorneroOS/installer](https://github.com/HorneroOS/installer) |
| Technical/user documentation | [HorneroOS/docs](https://github.com/HorneroOS/docs) |
| Product website | [HorneroOS/website](https://github.com/HorneroOS/website) |
| Organization-wide community files | [HorneroOS/.github](https://github.com/HorneroOS/.github) |

## Layout

- `manifests/` — release manifests pinning component versions.
- `profiles/` — distribution profiles and edition composition.
- `releases/` — release definitions and notes.
- `scripts/` — top-level orchestration helpers.

These directories are placeholders for now and will be filled in as the
composition tooling takes shape.

## Status

Early scaffolding. Nothing here is installable yet.

## License

[MIT](LICENSE).
