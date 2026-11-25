# GitHub activity contract (Dev Pulse)

`horneroctl github` is the normalized, read-only GitHub backend for
Dev Pulse (`hornero-github-stats`). All GitHub access goes through
the official GitHub CLI (`gh`) with literal argv (no shell): `gh`
owns authentication, and horneroctl never asks gh for a token, never
prints, logs or caches one, and never mutates anything on GitHub.

## Commands

| Command | Meaning |
|---|---|
| `github status` | The account `gh` is authenticated as, or an unavailable record explaining how to install `gh` and run `gh auth login` |
| `github stats [--days N] [--org O] [--repo owner/name] [--visibility all\|public\|private]` | Contribution calendar totals, streaks, per-repo commit contributions, and search-partitioned PR/issue totals |
| `github inbox` | Open authored PRs (with latest check state), review requests, assigned open issues, failing checks — each with its real GitHub URL |
| `github refresh [--clear-cache]` | Re-fetch past the cache, or clear the local cache |
| `github export [--format json\|csv\|markdown] [--output FILE] [--public-only]` | A local report; `--public-only` drops private repository names |

## Records (schemaVersion 1)

`--json` data carries `schemaVersion`, `scope: "account"`, `count`,
`stale`, `collectedAtUnix`, and `records` (a JSON-encoded array, the
agent-usage records pattern). Record kinds: `status`,
`stats-calendar`, `stats-repo`, `stats-totals`, `inbox`,
`inbox-summary`.

Rules:

- Unknown metrics are **omitted, never zero-filled**; failures appear
  in `errors[]` with status `unavailable`/`error`.
- Dates are actual event dates. PR/issue totals come from Search
  `total_count` partitioned by window/filter, never from counting
  returned items, so the search result cap cannot silently truncate
  a total. Inbox item lists are capped at 25 per category and the
  matching `inbox-summary` flags `truncated`.
- Contributions are the ones GitHub recognizes
  (`contributionsCollection`), not every commit on every branch.
  Calendar days are genuine reported days only; missing days are
  never interpolated, and streaks are computed over those days.
- GitHub figures are account-scope and are never summed with
  machine-local figures (agent usage tokens, local git).

## Cache and privacy

Normalized records are cached under
`$XDG_CACHE_HOME/hornero/github/` (dir 0700, files 0600, payload
only — never credentials), with a short TTL and stale labelling.
`github refresh --clear-cache` deletes it. Exports stay local unless
the user shares them.

## Coverage limits

- Review outcome splits (approvals vs changes requested) are not
  exposed by `contributionsCollection`; the calendar reports total
  review contributions only.
- Historical star/fork growth is not available retroactively and is
  never invented.
