# Normalized AI-agent usage contract

Status: implemented in `horneroctl agent usage` (hornero#407, Extensions 2.0).
Source: `cli/modules/hornero_core/agent_usage.v`; fixtures:
`cli/modules/hornero_core/agent_usage_test.v`.

Collectors emit one provider-independent record per agent; shell and
plugins consume **only** this normalized shape — the
`hornero-ai-usage` flagship must never parse a provider's raw store
itself. The pre-existing `horneroctl assistant usage --json` contract
(Hermes aggregates, hornero#398) is unchanged and is reused verbatim
by the `javi-hermes` collector.

## Record (schemaVersion 1)

`horneroctl agent usage [id] --json` returns the standard envelope;
`data.records` is the JSON array below and flat `usage.<provider>.*`
keys mirror the headline fields for simple consumers.

| Field | Meaning |
| --- | --- |
| `schemaVersion` | `1` |
| `provider` | Agent-registry id: `javi-hermes`, `codex`, `claude-code`, `muse`, `opencode` |
| `account` | Always `unknown` in this slice: deriving it would require reading credential files |
| `source` | Collector source kind (table below) |
| `status` | `ok` \| `unavailable` \| `error` |
| `freshness` | `fresh` (source mtime ≤ 24 h) \| `stale` \| `unknown` |
| `periodStart` / `periodEnd` | Earliest/latest timestamp the source itself reports; empty = all recorded history |
| `measuredAtUnix` | Source file mtime (seconds), omitted when unknown |
| `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`, `reasoningTokens`, `totalTokens` | Present only when `status=ok`; `totalTokens` = input+output |
| `sessions`, `apiCalls` | Present only when the source knows them |
| `models` | `name:tokens` joined by `,`, omitted when unknown |
| `quota` | `unknown` unless the provider's own record carried an official quota snapshot (`available`) |
| `quotaUsedPercent`, `quotaWindowMinutes`, `quotaResetsAtUnix` | Only with `quota=available` |
| `balance` | `unknown` unless the provider's own record carried one |
| `errors` | Human-readable per-provider problems; never file contents |

## Truthfulness rules

- No invented quota, limits, resets, or costs. There is no cost field
  at all; provider-recorded cost columns/keys are deliberately not
  read into this contract.
- Errors are never zeros: a missing/unreadable/empty source yields
  `unavailable`/`error` with an `errors` entry and no numeric fields
  (flat keys say `unknown`). Exit code is 1 when no collector produced
  data, with per-provider records still present in JSON output.
- Credentials are never read, returned, or logged. No network calls,
  no subprocesses; every source is a local read-only file/SELECT.
  Remote quota endpoints (which would need OAuth/API keys) are out of
  scope for this slice, so quota stays `unknown` except where the
  provider already wrote it into its local record.

## Collectors

| Provider | Source | Notes |
| --- | --- | --- |
| `javi-hermes` | `hermes-state-db` | Reuses `assistant_usage_report_at` over `$HERMES_HOME/state.db`; quota `unknown` (Hermes has no subscription of its own) |
| `codex` | `codex-rollout-jsonl` | Sums `token_count.info.last_token_usage` (never cumulative totals) under `$CODEX_HOME/sessions`; latest event's `rate_limits.primary` (used %, window, `resets_at`) and `credits.balance` are Codex's own recorded quota/balance |
| `claude-code` | `claude-stats-cache` | `modelUsage` aggregates from `$CLAUDE_CONFIG_DIR/stats-cache.json` (the CLI's own cache; raw transcripts are not rescanned — fork/resume copies double-count); period = `firstSessionDate`…`lastComputedDate` |
| `muse` | `muse-session-jsonl` | `payload.event.record.quantity` records under the Muse session store, deduplicated by `usage_id`; the Muse key-endpoint quota is never probed (credential) |
| `opencode` | `opencode-session-db` | `session` table aggregates in `$OPENCODE_DB` (read-only SELECT) |

JSONL scans are capped at 5 000 files; hitting the cap is reported in
`errors` and totals then understate, never overstate.

## Compatibility

Additive only: `assistant usage` keeps its exact #398 fields, and all
33 shipped plugins are unaffected (none consumes this command yet).
Migrating `hornero-ai-usage` from `assistant usage` to the normalized
records is follow-up work in the plugins repo, not part of #407.
