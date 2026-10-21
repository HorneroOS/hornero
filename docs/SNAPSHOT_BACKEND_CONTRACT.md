# Snapshot backend contract (spike, hornero#179)

Status: **contract only — no backend ships today.** `horneroctl` has
no system rollback, and no HorneroOS surface may claim one until the
VM proof below passes. The config-level tools in
`docs/UPDATE_RECOVERY.md` are settings archives, not system
snapshots.

## Decision

**Target backend: Btrfs snapshots (snapper-style timeline), gated on
the installer-owned layout acceptance (HorneroOS/installer#11).**
Implementation is explicitly deferred until that acceptance exists,
because every contract operation below depends on the real
subvolume layout, bootloader, and ESP/LUKS arrangement that the
installer owns.

Considered and rejected for this contract:

- **chezmoi/config archive** — restores Hornero configuration roots
  only. It cannot restore package files, kernels, boot entries, or a
  broken `ldconfig`/database state. It is not a system snapshot
  backend; the two layers must never be conflated in UI or docs.
- **OSTree / Nix-style generations** — a different deployment model
  that would replace the Arch/pacman transaction model. Out of
  scope by issue, not re-litigated here.
- **Filesystem-agnostic file copying (rsync-style system copies)** —
  no atomicity across a package transaction and no boot integration;
  failure modes dominate the benefit.

## Contract a backend must satisfy before any UI or CLI exposure

1. **Create** — take a snapshot pair (pre/post) around a package
   transaction, atomically with respect to the root subvolume.
2. **Enumerate** — list snapshots with timestamp, trigger (manual /
   pre / post transaction), and the package-state delta if known.
3. **Validate** — prove a snapshot is complete and self-consistent
   (subvolume present, not partially GC'd, boot assets coherent)
   before it is offered as a recovery target.
4. **Boot** — a previous state must be selectable from the boot
   menu without a working root session, including after a kernel
   or initramfs update that broke the current state.
5. **Restore** — restore returns root (and only root; never user
   home data) to the selected state, and the machine boots into it.
6. **Retention/GC** — bounded retention (count + age), GC never
   removes the snapshot the system is currently booted from, and
   GC failure is reported, not silent.

## Failure modes that must be handled or declared unsupported

- **Non-Btrfs installs** (ext4 and others): backend unsupported;
  reporting must say so plainly, not degrade silently.
- **ESP space exhaustion**: boot-entry/snapshot metadata writes
  must fail before the transaction, never mid-upgrade.
- **LUKS**: snapshot boot paths must still require unlock; a
  snapshot must never bypass the encryption boundary.
- **Partial transactions**: an interrupted `pacman` run must not
  leave a "post" snapshot claiming success.
- **Home subvolume**: restore never rolls back user data unless a
  future, separately-consented feature says so.

## VM proof (acceptance, blocked on installer#11)

Disposable VM, in order, with the transcript recorded on #179:

1. Install from the accepted installer layout; first boot.
2. `snapshot create` (or transaction pair) on a known-good system.
3. Deliberately break the system with a bad upgrade.
4. Reboot; select the previous state from the boot menu; confirm a
   working desktop.
5. Restore; confirm package state matches the snapshot point.
6. Exercise GC to the retention bound; confirm the booted-from
   snapshot survives.

Until all six steps are recorded, release readiness keeps its
updates/rollback gate at FAIL and docs keep saying there is no
HorneroOS system rollback.

## Non-goals

- Shipping `horneroctl rollback` (out of scope for the spike).
- Changing the install layout (installer-owned).
- Claiming snapshot availability in `package status` beyond the
  honest `none` it reports today.
