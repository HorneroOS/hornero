# Extension ecosystem ledger

Updated: 2026-11-13.
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
| Plugins batch 6 | `hornero-text-tools` (Uppercase/Lowercase/Title Case/Reverse transforms with live character, word and line counts), `hornero-color-converter` (validated `#RGB`/`#RRGGBB` hex to RGB and HSL, and RGB inputs back to hex; invalid hex shows an error), `hornero-json-tools` (Format with 2-space indentation and Minify using JSON parse/stringify only; parser errors shown), `hornero-base-converter` (validated decimal integer within safe range to binary, octal and hex, and hex back to decimal; invalid digits show errors), `hornero-date-calculator` (validated `YYYY-MM-DD` real dates, days-between and add-days results using UTC math to avoid DST drift); pure QML/JS, no eval/Process/network; catalog regenerated to 33 plugins | plugins#19 | verified (validators + 20 passed/1 skipped, qmllint clean, executed node probes for color/JSON/base/date/DST, review APPROVE, per PR; merged 2026-11-13, merge commit `adf3d2d`) |
| Website catalog 33 | Extensions catalog sync to the 33 batch-6 plugins: plugins pinned to `b49d976` (after the plugins#20 catalog-freshness fix), `extensions.json` regenerated via `data:sync` (never hand-edited) | website#218 | verified (merged 2026-11-13; build, `data:check` PASS, review pin finding fixed and re-verified) |
| Catalog freshness fix | `gen_catalog.py --check` no longer byte-compares the `generatedFrom` stamp (squash merges rewrite the stamped commit, so every squash-merged catalog landed red on main); freshness now compares plugin entries and validates the stamp shape, with `tests/test_gen_catalog.py` | plugins#20 | verified (24 passed/1 skipped locally, `validate` green on plugins main `b49d976`) |
| Shell staging build proof | Full CMake build of shell main `3518b33` (81 targets) installed with `DESTDIR` staging lists all 11 PluginKit facades (`Theme`, `Settings`, `Notifications`, `Desktop`, `System`, `Network`, `Media`, `Weather`, `Time`, `Power`, `Audio`) under `usr/lib/qt6/qml/Hornero/PluginKit/` — the next `hornero-shell` package built from main ships PluginKit; the installed 1.2.56 predates the merges. A nested headless-compositor live run was attempted and is **not** claimed: aquamarine requires a seat/DRM or parent Wayland backend unavailable to the isolated attempt | hornero (this ledger) | verified (build + staged file listing); live session still pending (see below) |
| Offscreen render evidence | 8 plugins rendered offscreen (Qt offscreen platform, unmodified `Main.qml` files, driven inputs/buttons, PNG-inspected): `hornero-text-tools` (counts 19/3/1 and `HELLO HORNERO WORLD` after clicking Uppercase), `hornero-json-tools` (Format pretty-prints driven JSON), `hornero-color-converter` (`#336699` → RGB 51/102/153, HSL 210/50%/40%, swatch + outline border), `hornero-base-converter`, `hornero-date-calculator`, `hornero-calculator`, `hornero-pomodoro` and `hornero-countdown` bar items; screenshots in `docs/extension-renders/`. Caveats: `Theme` was a test double mirroring the real facade's property set with the shell's real dark palette values (facade/member audit confirms every member used by all 33 plugins exists on shell main), Qt Controls used the Basic style, and baseline bar widgets colour via the system palette, so this is **not** live-shell evidence | hornero (this ledger) | verified as offscreen renders only; live shell session still pending (see below) |

## Extensions 2.0 — merged deliverables (verified 2026-11-13)

Every PR below was cross-checked with `gh pr view` (state and
`mergedAt`) and every linked issue with `gh issue view` on
2026-11-13 before being written here. All 34 PRs listed are
`MERGED`. A merged PR is not the same as a closed issue: where the
issue is still `OPEN`, the residual column says so — those issues
were merged without a closing reference or still carry acceptance
scope beyond the merged slice, and must not be reported as done
until they are closed on GitHub.

### Workstream A — Shell platform (HorneroOS/shell)

| Issue | Issue state | Merged PR | Residual |
|---|---|---|---|
| [shell#369](https://github.com/HorneroOS/shell/issues/369) PluginKit UI primitives | CLOSED | [shell#381](https://github.com/HorneroOS/shell/pull/381) feat(pluginkit): add native UI primitives for plugins (merged 2026-11-13) | None recorded; live rendering unverified (below) |
| [shell#370](https://github.com/HorneroOS/shell/issues/370) PluginKit Tooltips | CLOSED | [shell#382](https://github.com/HorneroOS/shell/pull/382) feat(pluginkit): add host-owned UiTooltip (merged 2026-11-13) | None recorded; live rendering unverified (below) |
| [shell#352](https://github.com/HorneroOS/shell/issues/352) Native polkit agent | OPEN | [shell#383](https://github.com/HorneroOS/shell/pull/383) feat(polkit): add native Quickshell polkit agent (additive) (merged 2026-11-13) | Issue still OPEN; PR is additive and carried no closing reference |
| [shell#371](https://github.com/HorneroOS/shell/issues/371) PluginKit Popovers | CLOSED | [shell#384](https://github.com/HorneroOS/shell/pull/384) feat(pluginkit): add host-owned UiPopover (merged 2026-11-13) | None recorded; live rendering unverified (below) |
| [shell#372](https://github.com/HorneroOS/shell/issues/372) Responsive extension hosts | CLOSED | [shell#385](https://github.com/HorneroOS/shell/pull/385) feat(plugins): responsive host context for all surfaces (merged 2026-11-13) | None recorded; live rendering unverified (below) |
| [shell#373](https://github.com/HorneroOS/shell/issues/373) Manifest v2 multi-surface | OPEN | [shell#386](https://github.com/HorneroOS/shell/pull/386) feat(plugins): manifest v2 multi-surface entry points (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [shell#374](https://github.com/HorneroOS/shell/issues/374) Settings schema + generated UI | OPEN | [shell#387](https://github.com/HorneroOS/shell/pull/387) feat(plugins): typed settings schema and generated settings UI (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [shell#376](https://github.com/HorneroOS/shell/issues/376) Accessibility + keyboard contract | OPEN | [shell#388](https://github.com/HorneroOS/shell/pull/388) feat(pluginkit): accessibility and keyboard contract (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [shell#375](https://github.com/HorneroOS/shell/issues/375) Localization API | OPEN | [shell#389](https://github.com/HorneroOS/shell/pull/389) feat(pluginkit): plugin localization API and validation (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [shell#377](https://github.com/HorneroOS/shell/issues/377) Shared data providers | OPEN | [shell#390](https://github.com/HorneroOS/shell/pull/390) feat(pluginkit): shared data providers with subscriptions (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| — (actions broker fix, no linked issue) | — | [shell#391](https://github.com/HorneroOS/shell/pull/391) fix(plugins): accept capabilities.actions broker declarations (merged 2026-11-13) | Follow-up fix to the broker work in hornero#411; no issue to close |
| [shell#378](https://github.com/HorneroOS/shell/issues/378) Composable dashboard layout | OPEN | [shell#392](https://github.com/HorneroOS/shell/pull/392) feat(plugins): responsive persisted dashboard layout (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [shell#379](https://github.com/HorneroOS/shell/issues/379) Marketplace previews/metadata | OPEN | [shell#393](https://github.com/HorneroOS/shell/pull/393) feat(plugins): marketplace metadata and safe static previews (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [shell#380](https://github.com/HorneroOS/shell/issues/380) Diagnostics / safe mode | OPEN | [shell#394](https://github.com/HorneroOS/shell/pull/394) feat(plugins): diagnostics, polling budget and safe mode (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |

### Workstream A/B bridge — hornero CLI and contracts (HorneroOS/hornero)

| Issue | Issue state | Merged PR | Residual |
|---|---|---|---|
| [qa#39](https://github.com/HorneroOS/qa/issues/39) Gaming release readiness | OPEN | [hornero#409](https://github.com/HorneroOS/hornero/pull/409) feat(gaming): report GPU topology in gaming doctor (merged 2026-11-13) | qa#39 is broader release-readiness scope and remains OPEN; #409 is the GPU-doctor slice only |
| [hornero#407](https://github.com/HorneroOS/hornero/issues/407) Normalized AI-agent usage | OPEN | [hornero#410](https://github.com/HorneroOS/hornero/pull/410) feat(agent): normalized AI-agent usage collectors (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [hornero#408](https://github.com/HorneroOS/hornero/issues/408) Typed capability/action broker | OPEN | [hornero#411](https://github.com/HorneroOS/hornero/pull/411) feat(plugin): typed capability/action broker (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| — (manifest v2 acceptance tests, no linked issue) | — | [hornero#412](https://github.com/HorneroOS/hornero/pull/412) test(plugin): prove manifest v2 shapes install and enable (merged 2026-11-13) | Test-only PR; no issue to close |

### Workstream B — Plugins catalogue 2.0 (HorneroOS/plugins)

| Issue | Issue state | Merged PR | Residual |
|---|---|---|---|
| [plugins#21](https://github.com/HorneroOS/plugins/issues/21) Extension Quality Gate | OPEN | [plugins#34](https://github.com/HorneroOS/plugins/pull/34) feat(validate): add extension quality gate and audit (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#22](https://github.com/HorneroOS/plugins/issues/22) AI Usage 2.0 | OPEN | [plugins#35](https://github.com/HorneroOS/plugins/pull/35) feat(ai-usage): AI Usage 2.0 on normalized provider data (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#23](https://github.com/HorneroOS/plugins/issues/23) Now Playing 2.0 | OPEN | [plugins#36](https://github.com/HorneroOS/plugins/pull/36) feat(now-playing): Now Playing 2.0 native media surfaces (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#24](https://github.com/HorneroOS/plugins/issues/24) Productivity Timers 2.0 | OPEN | [plugins#37](https://github.com/HorneroOS/plugins/pull/37) feat(timers): Productivity Timers 2.0 (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#25](https://github.com/HorneroOS/plugins/issues/25) Audio Extensions 2.0 | OPEN | [plugins#38](https://github.com/HorneroOS/plugins/pull/38) feat(audio): Audio Extensions 2.0 (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#26](https://github.com/HorneroOS/plugins/issues/26) System Insight 2.0 | OPEN | [plugins#39](https://github.com/HorneroOS/plugins/pull/39) feat(system): System Monitors 2.0 (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#27](https://github.com/HorneroOS/plugins/issues/27) Weather & Astronomy 2.0 | OPEN | [plugins#40](https://github.com/HorneroOS/plugins/pull/40) feat(weather): Weather & Astronomy 2.0 (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#28](https://github.com/HorneroOS/plugins/issues/28) Time & Agenda 2.0 | OPEN | [plugins#41](https://github.com/HorneroOS/plugins/pull/41) feat(time): Time & Agenda 2.0 (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#29](https://github.com/HorneroOS/plugins/issues/29) Notes & Focus 2.0 | OPEN | [plugins#42](https://github.com/HorneroOS/plugins/pull/42) feat(notes): Notes & Focus 2.0 (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#30](https://github.com/HorneroOS/plugins/issues/30) Utility Tools 2.0 | OPEN | [plugins#43](https://github.com/HorneroOS/plugins/pull/43) feat(utilities): Utility Tools 2.0 launcher-first quick actions (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#31](https://github.com/HorneroOS/plugins/issues/31) Battery & Uptime 2.0 | OPEN | [plugins#44](https://github.com/HorneroOS/plugins/pull/44) feat(power): Battery & Uptime 2.0 (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#32](https://github.com/HorneroOS/plugins/issues/32) Desktop Widgets 2.0 | OPEN | [plugins#45](https://github.com/HorneroOS/plugins/pull/45) feat(desktop): Desktop Widgets 2.0 (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [plugins#33](https://github.com/HorneroOS/plugins/issues/33) Catalogue provenance | CLOSED | [plugins#46](https://github.com/HorneroOS/plugins/pull/46) docs(inventory): provenance schema 2 with verified licenses (merged 2026-11-13) | None recorded |

## Counts (recounted on plugins main, 2026-11-13)

- 33 plugins in `catalog.json`, all under `plugins/<id>/`:
  `hornero-agenda`, `hornero-ai-usage`, `hornero-base-converter`,
  `hornero-battery`, `hornero-calculator`, `hornero-calendar`,
  `hornero-color-converter`, `hornero-countdown`,
  `hornero-date-calculator`, `hornero-disk-usage`, `hornero-dual-clock`,
  `hornero-focus-card`, `hornero-json-tools`, `hornero-metronome`,
  `hornero-microphone`, `hornero-moon-phase`, `hornero-network-monitor`,
  `hornero-now-playing`, `hornero-pomodoro`, `hornero-quick-notes`,
  `hornero-quiet-notes`, `hornero-stopwatch`, `hornero-studio-audio`,
  `hornero-studio-jobs`, `hornero-sun-card`, `hornero-system-health`,
  `hornero-system-monitor`, `hornero-text-tools`,
  `hornero-unit-converter`, `hornero-uptime`, `hornero-volume`,
  `hornero-weather`, `hornero-world-clock`.
  Growth: 6 baseline → 12 (batch 1) → 17 (batch 2) → 20 (batch 3) →
  23 (batch 4) → 28 (batch 5) → 33 (batch 6).
- 53 inventory entries recounted on plugins main, 2026-11-13:
  20 researched competitive entries + 33 implemented (supersedes the
  48-entry batch-5 snapshot; recount before citing a live total).
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

## Verified live evidence

- Host lifecycle round-trip (2026-11-12, horneroctl
  v0.2.0-preview32-26-gc9aed3d on the development host):
  `plugin catalog` listed 28 plugins from the live remote;
  `catalog install hornero-uptime --yes` installed it as inert data;
  `enable` succeeded (official trust); `list` reported
  `hornero-uptime enabled=true`; `disable` and receipt-owned
  `remove` succeeded; final `list` returned to the 6 baseline
  official plugins. Note: horneroctl resolves the data home from
  the passwd entry, not `$HOME`, so the probe ran against the real
  (revertible) receipt set and restored it exactly.
- The same host already had the 6 baseline official plugins
  installed and enabled before this mission's batches.

## Pending real evidence (not PASS)

- Live shell runtime/visual: the facades (including Power's and
  Audio's live singleton values and Audio's user-initiated volume/mic
  controls), batch 1–6 plugins (including `hornero-volume`,
  `hornero-microphone` muted/volume-only behaviour,
  `hornero-system-health` honest unavailable states, batch-5
  Settings persistence in `hornero-quick-notes`/`hornero-metronome`,
  and batch-6 `hornero-text-tools`, `hornero-color-converter`,
  `hornero-json-tools`, `hornero-base-converter` and
  `hornero-date-calculator`), and the marketplace pane have host
  test and lint evidence only; none has been exercised visually in
  a running shell session. (The batch-5/6 pure-QML tools and two
  baseline bar widgets do have offscreen rendered-and-inspected
  evidence — see the render-evidence row above — which does not
  substitute for the live session.)
- Preview QA: no Preview VM/session run yet for installing, enabling,
  placing and disabling a batch plugin end-to-end, nor for the
  marketplace search/filter/detail flow (shell#366 records GUI
  runtime as pending Preview QA).
- Any live click-through from the website catalog to Control Center
  install is unevidenced.
- `hornero-ai-usage` against a live assistant backend (real
  tokens/calls/sessions/models, and the quota-unknown state observed
  live rather than in contract tests).

### Workstream C — Distribution and adjacent surfaces

| Issue | Issue state | Merged PR | Residual |
|---|---|---|---|
| [website#219](https://github.com/HorneroOS/website/issues/219) Extension Marketplace website | OPEN | [website#220](https://github.com/HorneroOS/website/pull/220) feat(extensions): render catalogue from Extensions 2.0 pins (merged 2026-11-13) | Issue still OPEN; no closing reference on PR |
| [greeter#40](https://github.com/HorneroOS/greeter/issues/40) Media pipeline manifests | CLOSED | [greeter#42](https://github.com/HorneroOS/greeter/pull/42) feat(media): provider-neutral manifest model with approval gate (merged 2026-11-13) | None recorded for #40; media content itself is gated by #39/#41 below |
| [greeter#39](https://github.com/HorneroOS/greeter/issues/39) Rights gate: Pexels redistribution | OPEN | — (no PR) | Pending user API key / permissions; blocked on rights clearance, not code |
| [greeter#41](https://github.com/HorneroOS/greeter/issues/41) Cinematic Argentina catalogue | OPEN | — (no PR) | Pending user API key / permissions; full media replacement not started in code |
| [hornero#373](https://github.com/HorneroOS/hornero/issues/373) Wi-Fi requires hornero-live password | OPEN | [installer#96](https://github.com/HorneroOS/installer/pull/96) fix(live): allow passwordless live user to join Wi-Fi (merged 2026-11-13) | hornero#373 still OPEN; installer#96 is the live-image slice, issue closes only after live verification |

### Workstream status summary

Status below is derived only from the `gh`-verified PR/issue audit
above; no separate audit document in this repo overrides it.

| Workstream | Scope | Verified merged | Open residual |
|---|---|---|---|
| A — Shell platform | shell PluginKit/hosts/manifest v2 (shell#381–#394) plus hornero broker/usage/v2 tests (hornero#410–#412) and GPU doctor (hornero#409) | 18 PRs MERGED (14 shell + 4 hornero) | shell#352, #373, #374, #375, #376, #377, #378, #379, #380 and hornero#407, #408, qa#39 still OPEN on GitHub |
| B — Plugins catalogue 2.0 | Quality gate and the twelve 2.0 plugin families plus provenance (plugins#34–#46) | 13 PRs MERGED | plugins#21–#32 still OPEN; only plugins#33 CLOSED |
| C — Distribution / adjacent | website catalogue, greeter media pipeline, installer live Wi-Fi slice | website#220, greeter#42, installer#96 MERGED | website#219, greeter#39, greeter#41, hornero#373 still OPEN; greeter content blocked on user API key/permissions |

Closed-issue count in this audit: shell#369, #370, #371, #372,
plugins#33 and greeter#40 are CLOSED; every other linked issue
above is OPEN as of 2026-11-13. "Merged" in this ledger therefore
means code landed on the owning repo's main — it does not mean the
tracking issue was accepted or closed.

## Extensions 2.0 — unverified live evidence (not PASS)

None of the Extensions 2.0 work above has live evidence yet. In
particular:

- No live-shell rendering: no Extensions 2.0 surface (PluginKit
  primitives, tooltips, popovers, responsive hosts, dashboard,
  marketplace previews, or any 2.0 plugin family) has been
  exercised visually in a running Hornero shell session built from
  the merged mains.
- Screenshots outstanding: there are no Extensions 2.0 screenshots
  in `docs/extension-renders/` or elsewhere in this repo; the
  existing renders cover only the earlier batch-5/6 offscreen work
  and do not evidence 2.0.
- QA scenarios PENDING: no HorneroOS/qa scenario run is recorded
  for Extensions 2.0 install/enable/place/disable, settings-schema
  UI, dashboard persistence, safe mode, or the marketplace flow;
  qa#39 (gaming release readiness) also remains OPEN. QA status
  for 2.0 is PENDING, never PASS.
- No live backend proof for AI Usage 2.0 against real provider
  data, no live polkit prompt proof for shell#383, no live
  greeter-media or live-ISO Wi-Fi proof for greeter#42 /
  installer#96, and no website-to-Control-Center click-through.

## Next steps

1. Close or explicitly re-scope the still-OPEN tracking issues
   above only after their acceptance criteria are checked against
   the merged PRs; do not bulk-close on merge alone.
2. Build and run the merged shell + hornero + plugins mains in a
   real session; capture and inspect screenshots for each 2.0
   surface and plugin family, then move items out of the
   unverified section with dated evidence.
3. Add/run HorneroOS/qa scenarios for 2.0 lifecycle, dashboard,
   settings, safe mode and marketplace flows; record PENDING
   until a run exists.
4. Unblock greeter#39/#41 with the user's API key/permissions and
   rights clearance before any media-pack work.
5. Verify installer#96 on a live image and only then close
   hornero#373; verify hornero#409's GPU output on real hardware
   as part of qa#39.

This ledger is documentation only; no V code changes accompany it.
