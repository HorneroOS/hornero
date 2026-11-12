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
| Developer guide | `docs/DEVELOPING.md` (472 lines, linked from README): manifest schema, placements, exact PluginKit facades/props, allowed imports + both validators, `horneroctl` lifecycle, starter template, catalog two-commit flow; verified sources only, security truth included | plugins#15 | verified (tests pass, review APPROVE, per PR) |
| Website catalog 20 | Extensions catalog synced to the 20 batch-3 plugins: plugins pinned to 9900f1c, `extensions.json` regenerated via `data:sync` (never hand-edited) | website#215 | verified (140-page build, `data:check` PASS, review APPROVE, per PR) |
| Audio facade | PluginKit `Audio` singleton over shell Audio service: read-only `volume`, `muted`, `sourceVolume`, `sourceMuted`, `hasSink`, `hasSource`; user-initiated `setVolume` (clamped via service)/increment/decrement/toggleMute/toggleSourceMute only (nothing changes on load); no PwNode leak | shell#368 | verified (54 tests, qmllint PASS, review APPROVE, per PR); live values pending (below) |
| Plugins batch 4 | `hornero-volume`, `hornero-microphone` (muted/volume only, never records), `hornero-system-health` (honest unavailable states); catalog regenerated to 23 plugins | plugins#16 | verified (validators pass, review APPROVE, per PR) |
| Audio in DEVELOPING | `Audio` facade documented in `docs/DEVELOPING.md`: exact props/functions from shell `Audio.qml`, clamped user-initiated controls only; catalog regenerated | plugins#17 | verified (review APPROVE, per PR) |
| Website catalog 23 | Extensions catalog synced to the 23 batch-4 plugins: plugins pinned to caa8bcf, `extensions.json` regenerated via sync (never hand-edited) | website#216 | verified (build, `data:check` PASS, review APPROVE, per PR) |
| Ledger batch 4 | This ledger extended with batch 4 (shell#368, plugins#16), developer guide (plugins#15) and website 20 (website#215); counts 23 plugins / 43 inventory / 7 data facades; pending live evidence not PASS | hornero#400 | verified (merged 2026-11-12) |
| Plugins batch 5 | `hornero-quick-notes` (persistent note via PluginKit Settings: declared `note`, loaded on completion, saved debounced 600 ms, truncated at 4096 chars), `hornero-calculator` (safe tokenizer/parser, no eval), `hornero-agenda` (ISO week, pure Date math), `hornero-sun-card` (honest not-configured/error states), `hornero-metronome` (persistent BPM via PluginKit Settings: declared `bpm`, default 96, clamped 40–208); Settings persistence noted for quick-notes and metronome; catalog regenerated to 28 plugins | plugins#18 | verified (validators pass, executed probes, ISO-week cross-checked vs Python `isocalendar`, review APPROVE, per PR) |

## Counts (recounted on plugins main, 2026-11-12)

- 28 plugins in `catalog.json`, all under `plugins/<id>/`:
  `hornero-agenda`, `hornero-ai-usage`, `hornero-battery`,
  `hornero-calculator`, `hornero-calendar`, `hornero-countdown`,
  `hornero-disk-usage`, `hornero-dual-clock`, `hornero-focus-card`,
  `hornero-metronome`, `hornero-microphone`, `hornero-moon-phase`,
  `hornero-network-monitor`, `hornero-now-playing`, `hornero-pomodoro`,
  `hornero-quick-notes`, `hornero-quiet-notes`, `hornero-stopwatch`,
  `hornero-studio-audio`, `hornero-studio-jobs`, `hornero-sun-card`,
  `hornero-system-health`, `hornero-system-monitor`,
  `hornero-unit-converter`, `hornero-uptime`, `hornero-volume`,
  `hornero-weather`, `hornero-world-clock`.
  Growth: 6 baseline → 12 (batch 1) → 17 (batch 2) → 20 (batch 3) →
  23 (batch 4) → 28 (batch 5).
- 48 inventory entries recounted on plugins main, 2026-11-12:
  20 researched competitive entries + 28 implemented (supersedes the
  43-entry batch-4 snapshot; recount before citing a live total).
- 7 PluginKit data facades: System, Network, Media, Weather, Time
  (shell#365), Power (shell#367) and Audio (shell#368). System,
  Network, Weather, Time and Power are read-only; Media and Audio
  expose only guarded, user-initiated controls. The full PluginKit
  module also carries the pre-existing Theme, Notifications, Desktop
  and Settings entries (11 entries in `qmldir`), which are not data
  facades and are not counted in the 7.

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

- Live shell runtime/visual: the facades (including Power's and
  Audio's live singleton values and Audio's user-initiated volume/mic
  controls), batch 1–5 plugins (including `hornero-volume`,
  `hornero-microphone` muted/volume-only behaviour,
  `hornero-system-health` honest unavailable states, and batch-5
  Settings persistence in `hornero-quick-notes`/`hornero-metronome`),
  and the marketplace pane have host test and lint evidence only;
  none has been exercised visually in a running shell session.
- Preview QA: no Preview VM/session run yet for installing, enabling,
  placing and disabling a batch plugin end-to-end, nor for the
  marketplace search/filter/detail flow (shell#366 records GUI
  runtime as pending Preview QA).
- Website catalog beyond the 23-plugin sync (website#216) to the
  full 28, and any live click-through from catalog to Control Center
  install, are likewise unevidenced.
- `hornero-ai-usage` against a live assistant backend (real
  tokens/calls/sessions/models, and the quota-unknown state observed
  live rather than in contract tests).

This ledger is documentation only; no V code changes accompany it.
