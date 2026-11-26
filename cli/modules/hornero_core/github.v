module hornero_core

import os
import os.filelock
import time
import x.json2

// GitHub development-activity backend (Dev Pulse). All GitHub access
// goes through the official `gh` CLI with literal argv: gh owns
// authentication, and this module never asks gh for a token, never
// logs one, and never caches one. Records follow the agent-usage
// contract: unknown numbers are omitted (never zero-filled), failures
// surface in errors[], and GitHub (scope 'account') figures are never
// summed with machine-local figures.

pub const github_schema_version = 1
pub const github_cache_ttl_sec = i64(300)
pub const github_cache_stale_max_sec = i64(3600)
pub const github_search_cap = 100

pub struct GithubOptions {
pub mut:
	days       int = 90
	org        string
	repo       string
	visibility string = 'all' // all|public|private
	force      bool
	dry_run    bool
}

fn github_bin() string {
	override := os.getenv('HORNERO_GITHUB_BIN')
	if override.len > 0 {
		return override
	}
	return find_on_path('gh')
}

fn github_offline() bool {
	return os.getenv('HORNERO_GITHUB_OFFLINE') == '1'
}

fn github_run(args []string, dry_run bool) ExecReport {
	bin := github_bin()
	if bin.len == 0 {
		return ExecReport{
			command_line: command_line('gh', args)
			ok:           false
			output:       'gh (GitHub CLI) not found on PATH. Install github-cli and run: gh auth login'
			exit_code:    127
		}
	}
	return run_exec(ExecSpec{
		prog:        bin
		args:        args
		dry_run:     dry_run
		timeout_sec: 30
	})
}

fn github_cache_dir() string {
	return os.join_path(resolve_paths().cache_dir, 'hornero', 'github')
}

fn github_cache_read(name string) (string, i64) {
	raw := os.read_file(os.join_path(github_cache_dir(), '${name}.json')) or { return '', 0 }
	decoded := json2.decode[json2.Any](raw) or { return '', 0 }
	root := agent_usage_map(decoded)
	return json_str(root, 'payload'), agent_usage_i64(root, 'fetchedAtUnix')
}

fn github_cache_write(name string, payload string) {
	dir := github_cache_dir()
	os.mkdir_all(dir) or { return }
	os.chmod(dir, 0o700) or {}
	path := os.join_path(dir, '${name}.json')
	mut lock_file := filelock.new_file('${path}.lock')
	lock_file.acquire() or { return }
	defer {
		lock_file.release()
	}
	mut m := map[string]json2.Any{}
	m['fetchedAtUnix'] = json2.Any(time.now().unix())
	m['payload'] = payload
	os.write_file(path, json2.encode(m, escape_unicode: true)) or { return }
	os.chmod(path, 0o600) or {}
}

fn github_cache_key(kind string, o GithubOptions) string {
	mut raw := '${kind}|${o.days}|${o.org}|${o.repo}|${o.visibility}'
	raw = raw.replace('/', '_').replace(' ', '_')
	return raw
}

fn github_date(unix i64) string {
	return time.unix(unix).strftime('%Y-%m-%d')
}

fn github_window_from(days int) i64 {
	d := if days > 0 { days } else { 90 }
	return time.now().unix() - i64(d) * 86400
}

// github_record builds one string-encoded JSON record (agent-usage
// records pattern: a JSON array carried inside a data string).
fn github_record(fields map[string]json2.Any) json2.Any {
	return json2.Any(fields)
}

fn github_base_record(kind string) map[string]json2.Any {
	mut m := map[string]json2.Any{}
	m['source'] = 'github'
	m['scope'] = 'account'
	m['kind'] = kind
	m['collectedAtUnix'] = json2.Any(time.now().unix())
	return m
}

fn github_fail_record(kind string, msg string) map[string]json2.Any {
	mut m := github_base_record(kind)
	m['status'] = 'unavailable'
	m['errors'] = [json2.Any(msg)]
	return m
}

fn github_login() (string, string) {
	rep := github_run(['api', 'user'], false)
	if !rep.ok {
		return '', rep.output
	}
	decoded := json2.decode[json2.Any](rep.output) or { return '', 'gh api user returned invalid JSON' }
	root := agent_usage_map(decoded)
	login := json_str(root, 'login')
	if login.len == 0 {
		return '', 'gh api user returned no login (run: gh auth login)'
	}
	return login, ''
}

const github_graphql_stats = 'query(\$from: DateTime, \$to: DateTime) { viewer { login contributionsCollection(from: \$from, to: \$to) { totalCommitContributions restrictedContributionsCount totalIssueContributions totalPullRequestContributions totalPullRequestReviewContributions contributionCalendar { totalContributions weeks { contributionDays { date contributionCount } } } commitContributionsByRepository(maxRepositories: 25) { repository { nameWithOwner isPrivate owner { login } } contributions { totalCount } } } } }'

fn github_graphql(query string, vars map[string]string) (map[string]json2.Any, string) {
	mut args := ['api', 'graphql', '-f', 'query=${query}']
	for k, v in vars {
		args << '-F'
		args << '${k}=${v}'
	}
	rep := github_run(args, false)
	if !rep.ok {
		return map[string]json2.Any{}, rep.output
	}
	decoded := json2.decode[json2.Any](rep.output) or {
		return map[string]json2.Any{}, 'GitHub GraphQL returned invalid JSON'
	}
	root := agent_usage_map(decoded)
	if 'errors' in root {
		return map[string]json2.Any{}, 'GitHub GraphQL error: ${root['errors'].str()}'
	}
	return agent_usage_child(root, 'data'), ''
}

fn github_search_total(q string) (i64, string) {
	rep := github_run(['api', '-X', 'GET', 'search/issues', '-f', 'q=${q}', '-f', 'per_page=1'], false)
	if !rep.ok {
		return -1, rep.output
	}
	decoded := json2.decode[json2.Any](rep.output) or { return -1, 'search returned invalid JSON' }
	root := agent_usage_map(decoded)
	return agent_usage_i64(root, 'total_count'), ''
}

fn github_visibility_qualifier(v string) string {
	return match v {
		'public' { ' is:public' }
		'private' { ' is:private' }
		else { '' }
	}
}

fn github_filter_qualifier(o GithubOptions) string {
	mut q := ''
	if o.repo.len > 0 {
		q += ' repo:${o.repo}'
	} else if o.org.len > 0 {
		q += ' org:${o.org}'
	}
	q += github_visibility_qualifier(o.visibility)
	return q
}

// github_streaks returns (activeDays, currentStreak, longestStreak)
// from genuine calendar days only; missing days are never invented.
fn github_streaks(days []map[string]json2.Any) (int, int, int) {
	mut active := 0
	mut longest := 0
	mut run := 0
	for d in days {
		if agent_usage_i64(d, 'contributionCount') > 0 {
			active++
			run++
			if run > longest {
				longest = run
			}
		} else {
			run = 0
		}
	}
	// Current streak counts back from the last genuine day; today may
	// legitimately still be zero, so allow one trailing zero day.
	mut current := 0
	mut i := days.len - 1
	if i >= 0 && agent_usage_i64(days[i], 'contributionCount') == 0 {
		i--
	}
	for i >= 0 && agent_usage_i64(days[i], 'contributionCount') > 0 {
		current++
		i--
	}
	return active, current, longest
}

// github_collect_stats builds stats records without cache handling.
fn github_collect_stats(o GithubOptions) []map[string]json2.Any {
	login, lerr := github_login()
	if lerr.len > 0 {
		return [github_fail_record('stats', lerr)]
	}
	from_unix := github_window_from(o.days)
	from_iso := '${github_date(from_unix)}T00:00:00Z'
	to_iso := '${github_date(time.now().unix())}T23:59:59Z'
	data, gerr := github_graphql(github_graphql_stats, {
		'from': from_iso
		'to':   to_iso
	})
	if gerr.len > 0 {
		return [github_fail_record('stats', gerr)]
	}
	viewer := agent_usage_child(data, 'viewer')
	coll := agent_usage_child(viewer, 'contributionsCollection')
	mut records := []map[string]json2.Any{}
	// Calendar record
	mut cal := github_base_record('stats-calendar')
	cal['status'] = 'ok'
	cal['account'] = login
	cal['windowDays'] = json2.Any(i64(o.days))
	cal['windowFrom'] = github_date(from_unix)
	calendar := agent_usage_child(coll, 'contributionCalendar')
	cal['totalContributions'] = json2.Any(agent_usage_i64(calendar, 'totalContributions'))
	cal['totalCommitContributions'] = json2.Any(agent_usage_i64(coll, 'totalCommitContributions'))
	cal['restrictedContributions'] = json2.Any(agent_usage_i64(coll, 'restrictedContributionsCount'))
	cal['totalIssueContributions'] = json2.Any(agent_usage_i64(coll, 'totalIssueContributions'))
	cal['totalPullRequestContributions'] = json2.Any(agent_usage_i64(coll, 'totalPullRequestContributions'))
	cal['totalPullRequestReviewContributions'] = json2.Any(agent_usage_i64(coll, 'totalPullRequestReviewContributions'))
	mut daily := map[string]i64{}
	mut day_list := []map[string]json2.Any{}
	if 'weeks' in calendar && calendar['weeks'] is []json2.Any {
		for w in calendar['weeks'] as []json2.Any {
			week := agent_usage_map(w)
			if 'contributionDays' in week && week['contributionDays'] is []json2.Any {
				for d in week['contributionDays'] as []json2.Any {
					day := agent_usage_map(d)
					day_list << day
					date := json_str(day, 'date')
					if date.len == 10 {
						daily[date] = agent_usage_i64(day, 'contributionCount')
					}
				}
			}
		}
	}
	active, current, longest := github_streaks(day_list)
	cal['activeDays'] = json2.Any(i64(active))
	cal['currentStreak'] = json2.Any(i64(current))
	cal['longestStreak'] = json2.Any(i64(longest))
	cal['recentDays'] = agent_usage_daily_encode(daily)
	records << cal
	// Per-repo commit contribution records
	if 'commitContributionsByRepository' in coll
		&& coll['commitContributionsByRepository'] is []json2.Any {
		for entry in coll['commitContributionsByRepository'] as []json2.Any {
			e := agent_usage_map(entry)
			repo := agent_usage_child(e, 'repository')
			name := json_str(repo, 'nameWithOwner')
			if o.repo.len > 0 && name != o.repo {
				continue
			}
			if o.org.len > 0 && !name.starts_with('${o.org}/') {
				continue
			}
			mut r := github_base_record('stats-repo')
			r['status'] = 'ok'
			r['account'] = login
			r['repo'] = name
			r['visibility'] = if 'isPrivate' in repo && repo['isPrivate'].bool() {
				'private'
			} else {
				'public'
			}
			contribs := agent_usage_child(e, 'contributions')
			r['commitContributions'] = json2.Any(agent_usage_i64(contribs, 'totalCount'))
			records << r
		}
	}
	// Search-partitioned PR/issue totals (total_count is authoritative;
	// items are never used as totals, so the search cap cannot
	// silently truncate a count).
	filt := github_filter_qualifier(o)
	from_date := github_date(from_unix)
	mut totals := github_base_record('stats-totals')
	totals['status'] = 'ok'
	totals['account'] = login
	totals['windowFrom'] = from_date
	mut search_errs := []json2.Any{}
	searches := {
		'prsCreated':          'author:${login} type:pr created:>=${from_date}${filt}'
		'prsMerged':           'author:${login} type:pr merged:>=${from_date}${filt}'
		'prsClosedUnmerged':   'author:${login} type:pr closed:>=${from_date} is:closed is:unmerged${filt}'
		'prsOpen':             'author:${login} type:pr is:open${filt}'
		'issuesOpened':        'author:${login} type:issue created:>=${from_date}${filt}'
		'issuesClosed':        'author:${login} type:issue closed:>=${from_date}${filt}'
		'issuesAssignedOpen':  'assignee:${login} type:issue is:open${filt}'
		'reviewRequestedOpen': 'review-requested:${login} type:pr is:open${filt}'
	}
	for key, q in searches {
		total, serr := github_search_total(q)
		if serr.len > 0 {
			search_errs << json2.Any('${key}: ${serr}')
		} else {
			totals[key] = json2.Any(total)
		}
	}
	if search_errs.len > 0 {
		totals['errors'] = search_errs
		totals['truncated'] = json2.Any(true)
	}
	records << totals
	return records
}

const github_graphql_inbox = 'query($qMine: String!, $qReview: String!, $qAssigned: String!) { mine: search(type: ISSUE, query: $qMine, first: 25) { issueCount nodes { ... on PullRequest { title url createdAt updatedAt isDraft reviewDecision repository { nameWithOwner isPrivate } commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } review: search(type: ISSUE, query: $qReview, first: 25) { issueCount nodes { ... on PullRequest { title url createdAt updatedAt isDraft reviewDecision repository { nameWithOwner isPrivate } } } } assigned: search(type: ISSUE, query: $qAssigned, first: 25) { issueCount nodes { ... on Issue { title url createdAt updatedAt repository { nameWithOwner isPrivate } } } } }'

fn github_inbox_items(mut records []map[string]json2.Any, node map[string]json2.Any, category string, login string) {
	repo := agent_usage_child(node, 'repository')
	mut r := github_base_record('inbox')
	r['status'] = 'ok'
	r['account'] = login
	r['category'] = category
	r['repo'] = json_str(repo, 'nameWithOwner')
	r['visibility'] = if 'isPrivate' in repo && repo['isPrivate'].bool() {
		'private'
	} else {
		'public'
	}
	r['title'] = json_str(node, 'title')
	r['url'] = json_str(node, 'url')
	r['createdAt'] = json_str(node, 'createdAt')
	r['updatedAt'] = json_str(node, 'updatedAt')
	if 'isDraft' in node {
		r['draft'] = json2.Any((node['isDraft']).bool())
	}
	review_decision := json_str(node, 'reviewDecision')
	if review_decision.len > 0 && review_decision != 'null' {
		r['reviewDecision'] = review_decision
	}
	// Carry the latest check-rollup state on authored PRs; a failing
	// rollup additionally yields an actionable 'failing' record.
	if category == 'mine' {
		commits := agent_usage_child(node, 'commits')
		if 'nodes' in commits && commits['nodes'] is []json2.Any {
			nodes := commits['nodes'] as []json2.Any
			if nodes.len > 0 {
				c := agent_usage_map(nodes[0])
				commit := agent_usage_child(c, 'commit')
				rollup := agent_usage_child(commit, 'statusCheckRollup')
				state := json_str(rollup, 'state')
				if state.len > 0 {
					r['checks'] = state
				}
				records << r
				if state in ['FAILURE', 'ERROR'] {
					mut f := r.clone()
					f['category'] = 'failing'
					records << f
				}
				return
			}
		}
	}
	records << r
}

fn github_collect_inbox(o GithubOptions) []map[string]json2.Any {
	login, lerr := github_login()
	if lerr.len > 0 {
		return [github_fail_record('inbox', lerr)]
	}
	filt := github_filter_qualifier(o)
	data, gerr := github_graphql(github_graphql_inbox, {
		'qMine':     'is:pr is:open author:${login}${filt}'
		'qReview':   'is:pr is:open review-requested:${login}${filt}'
		'qAssigned': 'is:issue is:open assignee:${login}${filt}'
	})
	if gerr.len > 0 {
		return [github_fail_record('inbox', gerr)]
	}
	mut records := []map[string]json2.Any{}
	for pair in [['mine', 'mine'], ['review', 'review'], ['assigned', 'assigned']] {
		bucket := agent_usage_child(data, pair[0])
		if 'nodes' in bucket && bucket['nodes'] is []json2.Any {
			for n in bucket['nodes'] as []json2.Any {
				github_inbox_items(mut records, agent_usage_map(n), pair[1], login)
			}
		}
		mut summary := github_base_record('inbox-summary')
		summary['status'] = 'ok'
		summary['account'] = login
		summary['category'] = pair[1]
		summary['total'] = json2.Any(agent_usage_i64(bucket, 'issueCount'))
		summary['truncated'] = json2.Any(agent_usage_i64(bucket, 'issueCount') > 25)
		records << summary
	}
	return records
}

fn github_collect_status() []map[string]json2.Any {
	bin := github_bin()
	mut r := github_base_record('status')
	if bin.len == 0 {
		r['status'] = 'unavailable'
		r['errors'] = [json2.Any('gh (GitHub CLI) not found on PATH. On Arch: pacman -S github-cli, then gh auth login')]
		return [r]
	}
	login, lerr := github_login()
	if lerr.len > 0 {
		r['status'] = 'unavailable'
		r['errors'] = [json2.Any('GitHub authentication unavailable via gh: ${lerr}. Run: gh auth login')]
		return [r]
	}
	r['status'] = 'ok'
	r['account'] = login
	host := os.getenv('GH_HOST')
	r['host'] = if host.len > 0 { host } else { 'github.com' }
	r['ghPath'] = bin
	return [r]
}

fn github_render(command string, kind string, records []map[string]json2.Any, stale bool) CommandResult {
	mut data := map[string]string{}
	data['schemaVersion'] = github_schema_version.str()
	data['scope'] = 'account'
	mut any_ok := false
	mut lines := []string{}
	for r in records {
		if (r['status'] or { json2.Any('') }).str() == 'ok' {
			any_ok = true
		}
	}
	mut arr := []json2.Any{}
	for r in records {
		arr << github_record(r)
	}
	data['records'] = json2.encode(arr, escape_unicode: true)
	data['count'] = records.len.str()
	data['stale'] = stale.str()
	data['collectedAtUnix'] = time.now().unix().str()
	data['kind'] = kind
	if records.len > 0 {
		if acct := records[0]['account'] {
			data['account'] = acct.str()
		}
	}
	lines << '${command}: ${records.len} record(s)${if stale { ' (stale cache)' } else { '' }}'
	return CommandResult{
		command: command
		ok:      any_ok
		message: lines.join('\n')
		data:    data
	}
}

fn github_result(command string, kind string, o GithubOptions, collect fn (GithubOptions) []map[string]json2.Any) CommandResult {
	if o.dry_run {
		rep := github_run(['api', 'user'], true)
		mut data := map[string]string{}
		data['schemaVersion'] = github_schema_version.str()
		data['dryRun'] = 'true'
		data['backend'] = rep.command_line
		return CommandResult{
			command: command
			ok:      true
			message: 'dry-run: ${rep.command_line}'
			data:    data
		}
	}
	if github_offline() {
		return github_render(command, kind, [github_fail_record(kind, 'offline mode (HORNERO_GITHUB_OFFLINE=1)')], false)
	}
	key := github_cache_key(kind, o)
	if !o.force {
		payload, fetched := github_cache_read(key)
		if payload.len > 0 && time.now().unix() - fetched < github_cache_ttl_sec {
			decoded := json2.decode[json2.Any](payload) or { json2.Any('') }
			if decoded is []json2.Any {
				mut records := []map[string]json2.Any{}
				for item in decoded as []json2.Any {
					records << agent_usage_map(item)
				}
				return github_render(command, kind, records, false)
			}
		}
	}
	records := collect(o)
	mut ok_records := []map[string]json2.Any{}
	for r in records {
		ok_records << r
	}
	mut arr := []json2.Any{}
	for r in ok_records {
		arr << github_record(r)
	}
	github_cache_write(key, json2.encode(arr, escape_unicode: true))
	return github_render(command, kind, records, false)
}

// github_status_result reports the gh-authenticated account (or why not).
pub fn github_status_result(o GithubOptions) CommandResult {
	return github_result('github status', 'status', o, fn [o] (oo GithubOptions) []map[string]json2.Any {
		return github_collect_status()
	})
}

// github_stats_result reports normalized GitHub activity records.
pub fn github_stats_result(o GithubOptions) CommandResult {
	return github_result('github stats', 'stats', o, fn (oo GithubOptions) []map[string]json2.Any {
		return github_collect_stats(oo)
	})
}

// github_inbox_result reports actionable open GitHub items.
pub fn github_inbox_result(o GithubOptions) CommandResult {
	return github_result('github inbox', 'inbox', o, fn (oo GithubOptions) []map[string]json2.Any {
		return github_collect_inbox(oo)
	})
}

// github_refresh_result re-fetches past the cache and reports status.
pub fn github_refresh_result(o GithubOptions) CommandResult {
	mut forced := o
	forced.force = true
	_ = github_stats_result(forced)
	_ = github_inbox_result(forced)
	return github_status_result(forced)
}

// github_export_result renders a local report (json|csv|markdown)
// from the stats+inbox collectors. Public-only drops private repos.
pub fn github_export_result(o GithubOptions, format string, public_only bool, output string) CommandResult {
	mut records := github_collect_stats(o)
	records << github_collect_inbox(o)
	if public_only {
		mut kept := []map[string]json2.Any{}
		for r in records {
			if (r['visibility'] or { json2.Any('public') }).str() == 'private' {
				continue
			}
			kept << r
		}
		records = kept.clone()
	}
	mut content := ''
	match format {
		'json' {
			mut arr := []json2.Any{}
			for r in records {
				arr << github_record(r)
			}
			content = json2.encode(arr, escape_unicode: true)
		}
		'csv' {
			mut lines := ['kind,category,repo,title,url,createdAt,updatedAt']
			for r in records {
				lines << '${(r['kind'] or { json2.Any('') }).str()},${(r['category'] or { json2.Any('') }).str()},${(r['repo'] or { json2.Any('') }).str()},"${(r['title'] or { json2.Any('') }).str()}",${(r['url'] or { json2.Any('') }).str()},${(r['createdAt'] or { json2.Any('') }).str()},${(r['updatedAt'] or { json2.Any('') }).str()}'
			}
			content = lines.join('\n')
		}
		else {
			mut lines := ['# Dev Pulse report', '',
				'Window: last ${o.days} days${if public_only { ' (public only)' } else { '' }}',
				'Coverage: GitHub API via gh; unknown metrics are omitted, never zero-filled.',
				'']
			for r in records {
				kind := (r['kind'] or { json2.Any('') }).str()
				if kind.starts_with('stats') {
					lines << '- ${kind}: ${(r['repo'] or { json2.Any('') }).str()} totalContributions=${(r['totalContributions'] or { json2.Any('') }).str()} prsCreated=${(r['prsCreated'] or { json2.Any('') }).str()} prsMerged=${(r['prsMerged'] or { json2.Any('') }).str()}'
				} else if kind == 'inbox' {
					lines << '- [${(r['category'] or { json2.Any('') }).str()}] ${(r['repo'] or { json2.Any('') }).str()} — ${(r['title'] or { json2.Any('') }).str()} (${(r['url'] or { json2.Any('') }).str()})'
				}
			}
			content = lines.join('\n')
		}
	}
	mut data := map[string]string{}
	data['schemaVersion'] = github_schema_version.str()
	data['format'] = format
	if output.len > 0 {
		os.write_file(output, content) or {
			return fail_result('github export', 'cannot write ${output}: ${err.msg()}')
		}
		os.chmod(output, 0o600) or {}
		data['output'] = output
		return ok_result('github export', 'wrote ${output} (${format})', data)
	}
	data['content'] = content
	return ok_result('github export', content, data)
}

// github_clear_cache_result deletes the local GitHub cache.
pub fn github_clear_cache_result() CommandResult {
	dir := github_cache_dir()
	os.rmdir_all(dir) or {}
	return ok_result('github refresh', 'cleared GitHub cache at ${dir}', map[string]string{})
}
