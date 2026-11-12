# Extension ecosystem ledger

Updated: 2026-11-12.
Style follows [agentic-execution-ledger.md](agentic-execution-ledger.md).
Status key: verified = code merged on the owning repo's main plus the
tests/review recorded in the PR; pending = no real evidence yet (never
reported as PASS).

## Baseline — pre-existing v1 platform (do not rebuild)

Shipped before this mission and retained unchanged:

- Manifest: one `manifest.json` per plugin under `plugins/<id>/` in
  HorneroOS/plugins, with `Main.qml`, README and LICENSE alongside.
- Validator: `horneroctl plugin validate` plus the plugins-repo
  `validate_plugins` checks; `plugin enable` re-validates first and
  fails closed, leaving the plugin disabled on failure.
- Lifecycle: `horneroctl plugin new|install|install-local|remove|list|
  validate|enable|disable|trust|catalog|community`. Installs are inert
  (payload staged, hash receipt recorded, never loaded or enabled);
  enable is a separate, explicit consent step. See
  [PLUGIN_REGISTRY.md](PLUGIN_REGISTRY.md) for the signed community
  registry client (fails closed without the trust key; a registry
  signature proves publication, not review or safety).
- Catalog: official catalogue in HorneroOS/plugins (`catalog.json`,
  payload SHA-256 + pinned revision per entry), browsed via
  `horneroctl plugin catalog`.
- Pre-existing plugins (4 + 2): `hornero-pomodoro`,
  `hornero-dual-clock`, `hornero-focus-card`, `hornero-quiet-notes`,
  plus the Studio pair `hornero-studio-audio` and
  `hornero-studio-jobs`.

## Batches merged

| Batch | What shipped | PR | Status |
|---|---|---|---|
| Usage contract | `horneroctl assistant usage --json` stabilized for `hornero-ai-usage`: tokens/calls/sessions/models; quota explicitly `unknown`; error state, never zeros | hornero#398 | verified (merged 2026-11-12) |
| PluginKit facades | Five read-only PluginKit singletons wrapping shell services, copy-on-read for mutable lists; Media exposes only guarded user-initiated transport | shell#365 | verified (52 tests, qmllint PASS, review APPROVE) |
| Plugins batch 1 | `hornero-ai-usage` (flagship, on the usage contract), `hornero-system-monitor`, `hornero-network-monitor`, `hornero-now-playing`, `hornero-weather` (honest not-configured state), `hornero-calendar`; `inventory.yaml` created; catalog regenerated to 12 plugins | plugins#12 | verified (validators + 20 tests, per PR) |
| Marketplace UI | Control Center Extensions pane: search, trust/placement filters from live `horneroctl plugin list --json`, expandable detail with declared/verified capabilities; reuses existing lifecycle/catalog actions only | shell#366 | verified (54 pane tests, qmllint PASS, review APPROVE); GUI runtime pending (below) |
| Website catalog | Extensions catalog page synced to the 12 batch-1 plugins: in-process/no-sandbox truth, placement + trust filters, generated `extensions.json` (never hand-edited) | website#214 | verified (140-page build, links resolve, data:check PASS, per PR) |
| Plugins batch 2 | `hornero-world-clock` (per-row DST labels), `hornero-disk-usage`, `hornero-stopwatch`, `hornero-countdown`, `hornero-uptime`; catalog regenerated to 17 plugins | plugins#13 | verified (validators + 20 tests, per PR) |
| Power facade | PluginKit `Power` singleton over UPower: `hasBattery`, `percentage`, `charging`, `onBattery`, `stateText`; read-only scalars, no UPower object leak, no setters/Process | shell#367 | verified (53 tests, qmllint PASS, review APPROVE); live values pending (below) |
| Plugins batch 3 | `hornero-battery` (honest "No battery" state), `hornero-unit-converter`, `hornero-moon-phase` (labelled approximate); catalog regenerated to 20 plugins; inventory completed | plugins#14 | verified (validators + node probes, review APPROVE, per PR) |

## Counts (recounted on plugins main, 2026-11-12)

- 20 plugins in `catalog.json`, all under `plugins/<id>/`:
  `hornero-ai-usage`, `hornero-battery`, `hornero-calendar`,
  `hornero-countdown`, `hornero-disk-usage`, `hornero-dual-clock`,
  `hornero-focus-card`, `hornero-moon-phase`,
  `hornero-network-monitor`, `hornero-now-playing`, `hornero-pomodoro`,
  `hornero-quiet-notes`, `hornero-stopwatch`, `hornero-studio-audio`,
  `hornero-studio-jobs`, `hornero-system-monitor`,
  `hornero-unit-converter`, `hornero-uptime`, `hornero-weather`,
  `hornero-world-clock`. Growth: 6 baseline → 12 (batch 1) → 17
  (batch 2) → 20 (batch 3).
- 38 inventory entries as reported at batch-3 completion in
  plugins#14 (20 researched competitive entries + 18 implemented).
  Note: `inventory.yaml` on plugins main currently carries 40 `id:`
  entries (20 researched + 20 implemented) because the 2 pre-existing
  Studio plugins are also inventoried; cite 38 only for the batch-3
  snapshot, and recount before citing a live total.
- 6 PluginKit facades, all read-only: System, Network, Media, Weather,
  Time (shell#365) and Power (shell#367).

## Security truths (stated everywhere, not footnotes)

- Not sandboxed: plugin QML runs in-process in the shell with the
  user's privileges. Facades are a convenience and review surface;
  declared capabilities are review metadata, not an enforcement
  boundary. The marketplace detail view and the website catalog both
  say this explicitly.
- Install stays inert and enable stays a separate consent step;
  non-official plugins additionally need recorded trust for the
  current payload before they can be enabled.
- Quota unknown: the usage contract reports AI quota as `unknown`,
  never as a number or as zero; usage errors surface as an error
  state, not as zeroed counters.
- Community registry signatures prove publication only, not HorneroOS
  review; the production trust key is still not provisioned, so the
  community client fails closed (see PLUGIN_REGISTRY.md).

## Pending real evidence (not PASS)

- Live shell runtime/visual: the facades (including Power's live
  singleton values), batch 1–3 plugins, and the marketplace pane have
  host test and lint evidence only; none has been exercised visually
  in a running shell session.
- Preview QA: no Preview VM/session run yet for installing, enabling,
  placing and disabling a batch plugin end-to-end, nor for the
  marketplace search/filter/detail flow (shell#366 records GUI
  runtime as pending Preview QA).
- Website catalog beyond the batch-1 sync (12 plugins) to the full
  20, and any live click-through from catalog to Control Center
  install, are likewise unevidenced.
- `hornero-ai-usage` against a live assistant backend (real
  tokens/calls/sessions/models, and the quota-unknown state observed
  live rather than in contract tests).

This ledger is documentation only; no V code changes accompany it.
