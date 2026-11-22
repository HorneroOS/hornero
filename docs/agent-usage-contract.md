# Normalized AI-agent usage contract

Status: implemented in `horneroctl agent usage` (hornero#407, Agent Deck).
Source: `cli/modules/hornero_core/agent_usage.v` (local collectors) and
`agent_usage_quota.v` (provider quota probes); fixtures:
`cli/modules/hornero_core/agent_usage_test.v`.

Collectors emit one provider-independent record per discovered agent;
shell and plugins consume **only** this normalized shape — the
`hornero-ai-usage` flagship must never read a credential, call a
provider endpoint, or parse a provider store itself. The pre-existing
`horneroctl assistant usage --json` contract (Hermes aggregates,
hornero#398) is unchanged and is reused verbatim by the `javi-hermes`
collector.

## Concepts: harness is not subscription

A coding application (**harness**, e.g. OpenCode) is not always the
entity that owns a quota. Records therefore separate `harness` (the
app) from `provider` (whose allowance the windows describe), name the
`plan`/`billing` only when the provider reports them, and tag each
record's token figures with a `scope`: `local` (this machine's
activity) or `account` (provider-global). **Account-scope figures must
never be summed with local ones**, and quota windows from different
providers must never be averaged — consumers surface the most
constrained *verified* window instead.

## Record (schemaVersion 2)

`horneroctl agent usage [id] [--force-refresh] --json` returns the
standard envelope; `data.records` is the JSON array below and flat
`usage.<provider>.*` keys mirror the headline fields.

| Field | Meaning |
| --- | --- |
| `schemaVersion` | `2` |
| `provider` | Billing/usage provider id: `javi-hermes`, `codex`, `claude-code`, `muse`, `cursor`, `opencode` |
| `harness` | Coding application id (equals `provider` today) |
| `name` | Human label (`Claude Code`, `Cursor`, …) |
| `account` | Safe local identifier or `unknown`; never an email |
| `authStatus` | `signed-in` \| `authorization-needed` \| `unknown` |
| `plan` | Provider-reported plan/tier (`Max 5x`, `plus`, `Pro+`); omitted when unknown |
| `billing` | `subscription` \| `api` \| `unknown` |
| `source` | Collector source kind (table below) |
| `scope` | `local` \| `account` (Cursor figures are account-global) |
| `status` | `ok` \| `unavailable` \| `error` |
| `freshness` | `fresh` (local source mtime ≤ 24 h) \| `stale` \| `unknown` |
| `note` | Plain-language caveat (stale quota, rate limit, sign-in expired); omitted when none |
| `periodStart` / `periodEnd` | Earliest/latest timestamp the source itself reports |
| `measuredAtUnix` | Local source mtime (seconds), omitted when unknown |
| `collectedAtUnix` / `quotaCollectedAtUnix` | When the record / its quota windows were fetched |
| token fields, `sessions`, `apiCalls`, `models` | As in v1; present only when measured |
| `quota` | `unknown` unless the provider reported windows (`available`); **never a number, never 0%** |
| `quotaWindows[]` | `{id, label, usedPercent, metricKind: "official", windowMinutes?, resetsAtUnix?, note?}` — each window independent (5-hour, weekly, monthly, model-scoped, on-demand) |
| `quotaUsedPercent`, `quotaWindowMinutes`, `quotaResetsAtUnix` | v1 legacy mirror of the first window |
| `balance` | `unknown` unless the provider's own record carried one |
| `errors` | Human-readable per-provider problems; never file contents or secrets |

## Truthfulness rules

- No invented quota, limits, resets, plans, or costs. There is no cost
  field; provider-recorded cost columns are deliberately not read.
- Errors are never zeros: a missing/unreadable/empty source yields
  `unavailable`/`error` with an `errors` entry and no numeric fields.
  Exit code is 1 when no collector produced data.
- Provider percentages pass through as reported (Anthropic's `0.6`
  utilization is 0.6%); Hornero never derives a quota percentage from
  spend or from a plan name.
- A failed quota probe keeps local usage and explains itself in
  `note`; a rate-limited probe may show last-known-good windows with
  `quotaCollectedAtUnix` marking their real age.

## Credential scope B (user-approved)

Quota probing lives **only** in this backend. The QML UI spawns
nothing but `horneroctl` and holds no network capability.

- **Muse Code**: runs Muse's own `muse usage --json` (first-party,
  no model turn). Hornero reads no Muse credential.
- **Claude Code**: reads the OAuth access token Claude Code stored in
  `.credentials.json` **in memory only** and calls
  `GET https://api.anthropic.com/api/oauth/usage` (the endpoint behind
  Claude Code's own `/usage`). Expired tokens yield
  `authorization-needed`; the token is never refreshed by Hornero.
- **Cursor**: reads `cursorAuth/accessToken` from the editor's
  `state.vscdb` **in memory only** and calls the dashboard RPCs the
  Cursor CLI itself calls (`GetCurrentPeriodUsage`, `GetPlanInfo`,
  `GetAggregatedUsageEvents` on `api2.cursor.sh`). These are
  undocumented upstream endpoints; an unreadable reply degrades to
  `error`, never to guessed figures.
- **Codex / Hermes / OpenCode**: local read-only sources only.

Tokens are never returned, logged, cached, or written anywhere.
Accounts are never switched, refreshed, or revoked, and no inference
request is ever made to discover quota. Probe responses (usage JSON
only) are cached for 180 s under `$XDG_CACHE_HOME/hornero/agent-usage`
(`0700`/`0600`) so repeated UI reads do not hammer rate-limited
endpoints; `--force-refresh` bypasses the cache.

## Collectors

| Provider | Source | Quota |
| --- | --- | --- |
| `javi-hermes` | `hermes-state-db` | `unknown` (Hermes has no subscription of its own) |
| `codex` | `codex-rollout-jsonl` | latest rollout `rate_limits` primary **and** secondary windows + `plan_type` + credits balance |
| `claude-code` | `claude-stats-cache` + OAuth probe | `five_hour`, `seven_day`, and model-scoped `limits[]` windows; plan from the stored sign-in |
| `muse` | `muse-session-jsonl` + `muse usage --json` | session window + weekly, tier as plan |
| `cursor` | `cursor-dashboard-rpc` (scope `account`) | included-total / auto / named meters + on-demand budget; plan name; cycle token totals |
| `opencode` | `opencode-session-db` | `unknown` (per-provider balances are credential scope C, not enabled) |

JSONL scans are capped at 5 000 files; hitting the cap is reported in
`errors` and totals then understate, never overstate.

## Compatibility

v2 is additive over v1: every v1 key keeps its meaning, the legacy
scalar quota fields mirror the first window, and `assistant usage`
keeps its exact #398 fields. Consumers that only know v1 keep working;
the Agent Deck UI reads `quotaWindows` and falls back to the scalars.
