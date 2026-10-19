# Build toolchain

Hornero's CLI and composition builds use V, its bootstrap C snapshot, and its
TinyCC/libgc bundle pinned in [`toolchain/`](../toolchain/). The workflows share
the local composite action at `.github/actions/setup-v`; it builds without
updating upstream branches, so CI does not silently change compiler behavior
when the upstream repositories advance.

## Updating the V pin

1. Resolve full 40-character commits from the official V, VC, and TCC bundle
   repositories: `https://github.com/vlang/v`, `https://github.com/vlang/vc`,
   and `https://github.com/vlang/tccbin`. The TCC bundle ships one branch
   per target triplet, so it has two pins: `tcc.commit`
   (thirdparty-linux-amd64) and `tcc-arm64.commit`
   (thirdparty-linux-arm64); `setup-v` selects by runner architecture.
2. Update `toolchain/vlang.commit`, `toolchain/vc.commit`, and both TCC
   pins in one pull request. V's normal build updates its VC
   and TinyCC branches, so the shared action supplies all three locked
   checkouts and uses GNUmakefile's `local` mode to prevent those implicit
   network updates.
3. Let `horneroctl-ci`, `composition-ci`, and the release workflow build and
   test those exact compiler sources before merging the pins.
4. Record any upstream compiler regression or required workaround in the PR.

Do not replace the lock with a branch name or tag that can move. A compiler
update is complete only after Hornero's own build and test gates pass at the
new commit.
