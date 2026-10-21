# System updates and recovery boundaries

This document defines what the current `horneroctl` update and recovery
commands do. It is deliberately narrower than a system-update design: the
current release does not provide a Hornero-only update transaction or an
operating-system rollback mechanism.

## Current command lanes

| Command | Reads or changes | Does not guarantee |
| --- | --- | --- |
| `horneroctl package check` / `package updates` | Read-only repository update checks through `checkupdates`; optionally AUR checks through `yay -Qua` or `paru -Qua`; configured `IgnorePkg`, `IgnoreGroup`, and `HoldPkg` values through `pacman-conf` | These results are not limited to Hornero-owned packages. Missing AUR helpers or `pacman-conf` are reported as unchecked/unavailable, not as an empty result. |
| `horneroctl package upgrade --yes` | Runs `pkexec pacman -Syu`, a full Arch system upgrade | It is not a Hornero-only upgrade, does not hold or exclude the kernel, does not create a system snapshot, and does not promise rollback. |
| `horneroctl config snapshot create --yes` | Saves Hornero-owned configuration roots and package/host metadata under the user's Hornero data directory | It does not snapshot `/`, installed package files, boot entries, databases, home directories beyond the selected config roots, or kernel state. |
| `horneroctl config snapshot restore <id> --yes` | Creates a safety config snapshot, then restores the selected Hornero configuration archive | It is a configuration restore, not an OS rollback. |
| `horneroctl backup create` / `backup restore` | Archives/restores the explicitly configured Hornero config directory | It does not archive or restore the operating system. |

The term “snapshot” in the CLI means a **Hornero configuration snapshot**. It
must not be presented as a Btrfs, filesystem, bootable, or system snapshot.

The package check reports the effective pacman `IgnorePkg`, `IgnoreGroup`, and
`HoldPkg` values through `pacman-conf`. Pacman uses the ignore patterns to skip
matching upgrades during `--sysupgrade`. `HoldPkg` has a different meaning: it
prompts before removing matching packages and does not prevent upgrades. These
values provide visibility into configured policy, not a package hold
recommendation or rollback mechanism. `pacman-conf` resolves included
configuration files using pacman's own parser ([Arch pacman-conf manual](https://man.archlinux.org/man/pacman-conf.8.en),
[pacman.conf manual](https://man.archlinux.org/man/pacman.conf.5.en)).

## Ownership boundaries

- Hornero packages and the edition composition catalogue define which Hornero
  components are installed. Package-manager transactions still operate on the
  Arch package dependency graph, which can include packages outside Hornero.
- `package upgrade` delegates that entire dependency graph to pacman. The
  command does not claim kernel ownership or pin a kernel lane.
- The installer or administrator owns filesystem layout, boot configuration,
  and any system-level snapshot policy. `horneroctl` does not currently create
  or restore those snapshots.
- `config snapshot` and `backup` are user-level configuration recovery tools.
  Their scope is limited by their documented XDG paths and source overrides.

## Safe expectations today

1. Review `horneroctl package check` before choosing an update path.
2. The ignore-pattern report shows configured exclusions, but does not turn
   `package upgrade` into a Hornero-owned update lane.
3. Treat `horneroctl package upgrade --yes` as a full system upgrade, including
   any kernel package selected by the configured Arch repositories.
4. Use a separately configured filesystem/boot recovery strategy if the host
   requires system rollback. Hornero does not currently verify that strategy.
5. Use configuration snapshots for Hornero settings only. They can help undo
   a settings change but cannot recover a failed package transaction or an
   unbootable system.

No Hornero command performs an automatic update, installs a timer, changes
repository configuration, holds packages, or sends telemetry.

## Requirements before adding a Hornero update lane

A future product-owned update command needs a reliable package ownership
source, clear treatment of dependency updates, explicit kernel policy, a
transaction preview, interruption/error behavior, and a tested recovery
contract. The edition catalogue alone is not enough to safely update only
Hornero packages: package dependencies may require a wider pacman transaction.
Until those conditions are demonstrated in a disposable test system, the
product must keep the full-system `package upgrade` name and scope explicit.

Likewise, system rollback should only be exposed after a supported snapshot
backend can create, enumerate, validate, and restore snapshots across boot
and package state, with a real recovery test. A config archive is not a
substitute for that work. The backend decision, contract operations,
failure modes, and VM proof live in `docs/SNAPSHOT_BACKEND_CONTRACT.md`
(hornero#179; implementation deferred to installer layout acceptance).
