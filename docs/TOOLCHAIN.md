# Build toolchain

Hornero's CLI and composition builds use V and its bootstrap C snapshot pinned
in [`toolchain/`](../toolchain/). The workflows share the local composite action
at `.github/actions/setup-v`; it builds without updating upstream branches, so
CI does not silently change compiler behavior when V or VC `master` advances.

## Updating the V pin

1. Resolve full 40-character commits from the official V and VC repositories:
   `https://github.com/vlang/v` and `https://github.com/vlang/vc`.
2. Update both `toolchain/vlang.commit` and `toolchain/vc.commit` in one pull
   request. V's normal build updates its VC and TinyCC branches, so the shared
   action supplies the locked VC checkout and uses GNUmakefile's `local` mode
   to prevent those implicit network updates.
3. Let `horneroctl-ci`, `composition-ci`, and the release workflow build and
   test those exact compiler sources before merging the pins.
4. Record any upstream compiler regression or required workaround in the PR.

Do not replace the lock with a branch name or tag that can move. A compiler
update is complete only after Hornero's own build and test gates pass at the
new commit.
