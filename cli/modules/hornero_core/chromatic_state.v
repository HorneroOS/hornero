module hornero_core

import os
import time
import x.json2

// Chromatic state, snapshot history and the transactional commit
// (CHROMATIC-CONTRACT §6.2/§6.3).
//
//   $XDG_STATE_HOME/hornero/chromatic/state.json        what is applied
//   $XDG_STATE_HOME/hornero/chromatic/history/NNNN.json previous contents
//
// A snapshot stores the previous content of EVERY file a commit touches
// (`files`, plus their hashes in `outputs`) and the previous
// appearance.theme / appearance.chromatic, so rollback restores bytes, not
// guesses. The ring keeps the newest 10. A corrupt state or history file is
// renamed to `<name>.corrupt-<unix>`; apply keeps working and rollback skips
// corrupt entries.

const history_ring = 10

// HistoryEntry is one readable snapshot.
struct HistoryEntry {
	number int
	doc    map[string]json2.Any
}

fn snapshot_name(n int) string {
	return '${n:04}.json'
}

// quarantine renames an unreadable state file out of the way.
fn quarantine(path string) string {
	dest := '${path}.corrupt-${time.now().unix()}'
	os.rename(path, dest) or { return path }
	return dest
}

// snapshot_numbers lists the numeric prefixes of history files (corrupt
// leftovers included, so numbers stay monotonic), ascending.
fn snapshot_numbers() []int {
	files := os.ls(chromatic_history_dir()) or { return []int{} }
	mut nums := []int{}
	for f in files {
		if f.len >= 4 && f[..4].bytes().all(it >= `0` && it <= `9`) {
			nums << f[..4].int()
		}
	}
	nums.sort()
	return nums
}

// read_history returns readable snapshots newest first plus the files it
// had to quarantine.
fn read_history() ([]HistoryEntry, []string) {
	dir := chromatic_history_dir()
	mut entries := []HistoryEntry{}
	mut corrupt := []string{}
	for f in os.ls(dir) or { []string{} } {
		if f.len != 9 || !f.ends_with('.json') || !f[..4].bytes().all(it >= `0` && it <= `9`) {
			continue
		}
		path := os.join_path(dir, f)
		raw := os.read_file(path) or { continue }
		doc := parse_json_object(raw) or {
			corrupt << quarantine(path)
			continue
		}
		if jget(doc, 'schemaVersion') != '1' || 'files' !in doc {
			corrupt << quarantine(path)
			continue
		}
		entries << HistoryEntry{
			number: f[..4].int()
			doc:    doc
		}
	}
	entries.sort(a.number > b.number)
	return entries, corrupt
}

// read_chromatic_state loads state.json; an unreadable file is quarantined.
fn read_chromatic_state() (map[string]json2.Any, string) {
	path := chromatic_state_file()
	raw := os.read_file(path) or { return map[string]json2.Any{}, '' }
	doc := parse_json_object(raw) or {
		return map[string]json2.Any{}, quarantine(path)
	}
	if jget(doc, 'schemaVersion') != '1' {
		return map[string]json2.Any{}, quarantine(path)
	}
	return doc, ''
}

fn write_chromatic_state(g Generated, snapshot int) ! {
	chrom := jmap(g.scheme, 'chromatic')
	doc := {
		'schemaVersion': jint(1)
		'active':        jbool(true)
		'appliedAt':     jstr(chromatic_now_iso())
		'request':       json2.Any(jmap(chrom, 'request'))
		'resolved':      json2.Any(jmap(chrom, 'resolved'))
		'fingerprint':   jstr(g.fingerprint)
		'sourceKey':     chrom['sourceKey'] or { json2.Any(json2.Null{}) }
		'engine':        chrom['engine'] or { jstr('') }
		'algorithm':     chrom['algorithm'] or { jint(0) }
		'snapshot':      jstr('${snapshot:04}')
	}
	write_atomic_synced(chromatic_state_file(), json2.encode(doc, escape_unicode: true) + '\n')!
}

// mark_chromatic_inactive records that a curated theme replaced Chromatic.
fn mark_chromatic_inactive(snapshot int) {
	mut doc, _ := read_chromatic_state()
	if doc.len == 0 {
		return
	}
	doc['active'] = jbool(false)
	doc['snapshot'] = jstr('${snapshot:04}')
	write_atomic_synced(chromatic_state_file(), json2.encode(doc, escape_unicode: true) + '\n') or {}
}

// --- snapshot ----------------------------------------------------------------------

fn temp_path_for(path string) string {
	return os.join_path(os.dir(path), '.${os.file_name(path)}.chromatic.${os.getpid()}.tmp')
}

fn json_or_null(raw string, present bool) json2.Any {
	if !present {
		return json2.Any(json2.Null{})
	}
	return jstr(raw)
}

// write_snapshot stores the current contents of `paths` (and the current
// appearance keys) and prunes the ring. Returns the snapshot number.
fn write_snapshot(paths []string, reason string) !int {
	mut files := map[string]json2.Any{}
	mut outputs := map[string]json2.Any{}
	for path in paths {
		if os.is_file(path) {
			raw := os.read_file(path) or { '' }
			files[path] = jstr(raw)
			outputs[path] = jstr(chromatic_sha256(raw))
		} else {
			files[path] = json2.Any(json2.Null{})
			outputs[path] = json2.Any(json2.Null{})
		}
	}
	scheme_path := signal_scheme_file()
	mut scheme_doc := json2.Any(json2.Null{})
	mut theme_id := ''
	if raw := os.read_file(scheme_path) {
		if m := parse_json_object(raw) {
			scheme_doc = json2.Any(m)
			theme_id = jget(m, 'id')
		}
	}
	appearance := read_shell_appearance()
	shell_appearance := {
		'theme':     appearance['theme'] or { json2.Any(json2.Null{}) }
		'chromatic': appearance['chromatic'] or { json2.Any(json2.Null{}) }
	}
	nums := snapshot_numbers()
	number := if nums.len > 0 { nums.last() + 1 } else { 1 }
	doc := {
		'schemaVersion':   jint(1)
		'createdAt':       jstr(chromatic_now_iso())
		'reason':          jstr(reason)
		'themeId':         jstr(theme_id)
		'scheme':          scheme_doc
		'shellAppearance': json2.Any(shell_appearance)
		'outputs':         json2.Any(outputs)
		'files':           json2.Any(files)
	}
	write_atomic_synced(os.join_path(chromatic_history_dir(), snapshot_name(number)),
		json2.encode(doc, escape_unicode: true) + '\n') or {
		return error(cfail('chromatic.write-failed', 'cannot write snapshot: ${err.msg()}'))
	}
	prune_history()
	return number
}

fn prune_history() {
	dir := chromatic_history_dir()
	mut names := []string{}
	for f in os.ls(dir) or { []string{} } {
		if f.len == 9 && f.ends_with('.json') && f[..4].bytes().all(it >= `0` && it <= `9`) {
			names << f
		}
	}
	names.sort()
	for names.len > history_ring {
		os.rm(os.join_path(dir, names[0])) or {}
		names.delete(0)
	}
}

// --- commit -----------------------------------------------------------------------

fn restore_previous(path string, prev string, existed bool) {
	if existed {
		write_atomic_synced(path, prev) or {}
	} else {
		os.rm(path) or {}
	}
}

// commit_locked performs the transaction; the caller holds the appearance
// lock. Order: validate shell.json -> snapshot -> temp files (fsynced) ->
// rename in plan order (scheme first) -> shell.json last. Any failure
// restores every file already replaced and removes the new snapshot.
// HORNERO_CHROMATIC_FAIL_RENAME=N fails the Nth replace (1-based) for tests.
fn commit_locked(plan []PlannedWrite, patch ShellPatch, reason string) !int {
	shell_path := shell_config_file(resolve_paths())
	shell_new := patched_shell_json(patch)!
	shell_existed := os.is_file(shell_path)
	shell_prev := os.read_file(shell_path) or { '' }
	mut prev := map[string]string{}
	mut existed := map[string]bool{}
	mut paths := []string{}
	for w in plan {
		paths << w.path
		if os.is_file(w.path) {
			prev[w.path] = os.read_file(w.path) or { '' }
			existed[w.path] = true
		}
	}
	number := write_snapshot(paths, reason)!
	mut temps := []string{}
	cleanup := fn (temps []string) {
		for t in temps {
			os.rm(t) or {}
		}
	}
	for w in plan {
		if w.remove {
			continue
		}
		os.mkdir_all(os.dir(w.path)) or {
			cleanup(temps)
			os.rm(os.join_path(chromatic_history_dir(), snapshot_name(number))) or {}
			return error(cfail('chromatic.write-failed', 'cannot create ${os.dir(w.path)}: ${err.msg()}'))
		}
		tmp := temp_path_for(w.path)
		write_file_synced(tmp, w.content) or {
			cleanup(temps)
			os.rm(tmp) or {}
			os.rm(os.join_path(chromatic_history_dir(), snapshot_name(number))) or {}
			return error(cfail('chromatic.write-failed', err.msg()))
		}
		temps << tmp
	}
	shell_tmp := temp_path_for(shell_path)
	os.mkdir_all(os.dir(shell_path)) or {}
	write_file_synced(shell_tmp, shell_new) or {
		cleanup(temps)
		os.rm(shell_tmp) or {}
		os.rm(os.join_path(chromatic_history_dir(), snapshot_name(number))) or {}
		return error(cfail('chromatic.write-failed', err.msg()))
	}
	temps << shell_tmp
	fail_at := os.getenv('HORNERO_CHROMATIC_FAIL_RENAME').int()
	mut done := []string{}
	mut step := 0
	mut failure := ''
	for w in plan {
		step++
		if fail_at == step {
			failure = 'injected failure at replace ${step} (${w.path})'
			break
		}
		if w.remove {
			os.rm(w.path) or {}
		} else {
			os.rename(temp_path_for(w.path), w.path) or {
				failure = 'cannot replace ${w.path}: ${err.msg()}'
				break
			}
		}
		done << w.path
	}
	mut shell_done := false
	if failure.len == 0 {
		step++
		if fail_at == step {
			failure = 'injected failure at replace ${step} (${shell_path})'
		} else {
			os.rename(shell_tmp, shell_path) or {
				failure = 'cannot replace ${shell_path}: ${err.msg()}'
			}
			shell_done = failure.len == 0
		}
	}
	if failure.len > 0 {
		for path in done.reverse() {
			restore_previous(path, prev[path] or { '' }, existed[path] or { false })
		}
		if shell_done {
			restore_previous(shell_path, shell_prev, shell_existed)
		}
		cleanup(temps)
		os.rm(os.join_path(chromatic_history_dir(), snapshot_name(number))) or {}
		return error(cfail('chromatic.write-failed', '${failure}; previous state restored'))
	}
	return number
}

// chromatic_marker_in reports whether a file was generated by Chromatic.
fn chromatic_marker_in(path string) bool {
	raw := os.read_file(path) or { return false }
	return raw.len > 0 && raw[..if raw.len > 400 { 400 } else { raw.len }].contains(chromatic_marker)
}

// chromatic_template_outputs lists every output path of the known
// manifests that exists and carries the Chromatic marker.
fn chromatic_marked_outputs() []string {
	mut out := []string{}
	for m in list_template_manifests().manifests {
		path := jail_output(m.output) or { continue }
		if os.is_file(path) && chromatic_marker_in(path) {
			out << path
		}
	}
	return out
}

// chromatic_release_outputs removes Chromatic-generated template files once
// a curated theme owns the desktop again (kitty/GTK 4/Qt are re-pointed by
// the curated apply itself). Silent; never fails an apply.
pub fn chromatic_release_outputs() {
	live := read_signal_scheme() or { return }
	if live.id == chromatic_theme_id {
		return
	}
	for path in chromatic_marked_outputs() {
		os.rm(path) or {}
	}
}
