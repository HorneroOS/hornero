module hornero_core

import x.json2

fn day(count i64) map[string]json2.Any {
	return {
		'contributionCount': json2.Any(count)
	}
}

fn test_github_streaks_count_genuine_days_only() {
	active, current, longest := github_streaks([day(1), day(2), day(0), day(1), day(1), day(1)])
	assert active == 5
	assert longest == 3
	assert current == 3
	// A still-empty today does not break the current streak.
	active2, current2, longest2 := github_streaks([day(1), day(1), day(0)])
	assert active2 == 2
	assert current2 == 2
	assert longest2 == 2
	active3, current3, _ := github_streaks([day(0), day(0)])
	assert active3 == 0
	assert current3 == 0
}

fn test_github_filter_qualifier_validates_scope() {
	assert github_filter_qualifier(GithubOptions{}) == ''
	assert github_filter_qualifier(GithubOptions{ org: 'HorneroOS' }) == ' org:HorneroOS'
	assert github_filter_qualifier(GithubOptions{ repo: 'a/b', visibility: 'public' }) == ' repo:a/b is:public'
	assert github_filter_qualifier(GithubOptions{ visibility: 'private' }) == ' is:private'
}

fn test_github_fail_record_never_zero_fills() {
	r := github_fail_record('stats', 'boom')
	assert r['status'].str() == 'unavailable'
	assert 'totalContributions' !in r
	assert 'prsCreated' !in r
}
