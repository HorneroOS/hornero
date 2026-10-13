# Build toolchain

Hornero's CLI and composition builds use the V compiler pinned in
[`toolchain/vlang.commit`](../toolchain/vlang.commit). The workflows share the
local composite action at `.github/actions/setup-v`, so CI does not silently
change compiler behavior when upstream `master` advances.

## Updating the V pin

1. Resolve a full 40-character commit from the official V repository:
   `https://github.com/vlang/v`.
2. Update `toolchain/vlang.commit` in a pull request.
3. Let `horneroctl-ci`, `composition-ci`, and the release workflow build and
   test that exact compiler revision before merging the pin.
4. Record any upstream compiler regression or required workaround in the PR.

Do not replace the lock with a branch name or tag that can move. A compiler
update is complete only after Hornero's own build and test gates pass at the
new commit.
