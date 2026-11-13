# Typed plugin capability/action broker

`horneroctl plugin action` is the supported path for an installed Shell
extension that needs an OS action. It is a closed catalogue of narrow,
typed `horneroctl` contracts — never a generic command endpoint and
never a privileged shell. Read-only actions are separated from
mutating ones in the catalogue, in `plugin action list` output, and in
the CLI flag contract.

```sh
horneroctl plugin action list [plugin-id]
horneroctl plugin action check <plugin-id> <action> [arg]
horneroctl plugin action run <plugin-id> <action> [arg] [--dry-run|--yes]
```

`list` and `check` never execute anything. `check` simulates the exact
decision `run` would enforce. Mutating `run` calls additionally
require `--yes` at this trusted CLI.

## Gates (all fail closed)

A call runs only when every gate passes, in order:

1. The plugin id is well-formed and a Hornero receipt owns it; the
   payload and receipt are not symlinks.
2. The plugin is enabled and its current payload is trusted (official
   catalogue, hash-pinned local trust, or signed).
3. The installed manifest declares the action in the additive
   `capabilities.actions` string array.
4. The action exists in the closed broker catalogue
   (`plugin_broker_catalogue` in `cli/modules/hornero_core/plugin_broker.v`)
   and its typed argument validates. `theme_set` accepts only official
   theme ids, `window_focus` only hex window addresses, `notify` only
   bounded text, and `plugin_file_read` only a relative path that
   stays inside the plugin's own payload after symlink resolution.
5. The ABAC policy (`assistant_policy.v`, same engine as the Javi
   broker) allows principal `plugin` to perform the mapped action on
   the exact resource. The read-only preset grants the plugin
   principal `desktop.observe`, `desktop.window.list`, and
   `filesystem.read` inside its own payload (the payload is passed as
   the workspace root). Every mutation — `appearance.modify`,
   `desktop.window.focus`, `notifications.send` — is default-denied
   until the user writes an explicit rule for principal `plugin` in
   the policy file; an `approval` rule is satisfied only by the
   human's `--yes`, bound to that one exact action+resource and never
   persisted. Hard denies (protected paths) cannot be overridden.

Every `run` outcome — allowed, denied, undeclared, unknown — is
appended to a bounded audit log at
`$XDG_STATE_HOME/hornero/plugins/action.log` (0600).

## Manifest compatibility

`capabilities.actions` is additive and opt-in. Manifests written
before it existed — including every currently shipped plugin
manifest — declare no broker actions and keep loading identically in
`plugin list`, `plugin validate`, the catalogue, and the Shell,
because no existing reader looks at the new field. Adding the field
changes the payload hash, so a locally trusted plugin must be
re-trusted and re-enabled through the existing lifecycle after its
manifest changes; the broker never bypasses that.

Example declaration:

```json
"capabilities": {
  "processCommands": ["horneroctl"],
  "networkHosts": [],
  "settings": {},
  "actions": ["system_info", "plugin_file_read"]
}
```

## Honest security boundary

QML plugins are **not sandboxed**. Quickshell QML runs with the
logged-in user's permissions, so a malicious or compromised plugin can
ignore this broker and act directly. Manifest capability declarations
(including `capabilities.actions`) are declarations that support
review; they are not enforcement and not a security certification.
What this broker does enforce is its own surface: calls made through
`horneroctl plugin action run` are typed, declaration-checked,
policy-decided, and audited, and there is no way to widen them into
arbitrary or privileged command execution. Prefer the broker in
well-behaved extensions so their OS actions stay visible and
revocable; do not treat its existence as plugin confinement.

## Validation

```sh
cd cli
./make.vsh test
./make.vsh fmt-check
./make.vsh vet
./make.vsh build-cli
```

Negative coverage lives in
`cli/modules/hornero_core/plugin_broker_test.v`: path traversal,
absolute paths, symlink target and symlinked-directory escapes,
traversal-shaped plugin ids, uninstalled/disabled/untrusted plugins,
undeclared and unknown actions, shell-shaped action names, malformed
`capabilities.actions`, and the read-only ABAC baseline for the
`plugin` principal.
