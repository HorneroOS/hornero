module hornero_core

import os
import time
import x.json2

// User-scoped Studio render-job API and safe queue lifecycle
// (HorneroOS/hornero#289). Jobs are explicit, typed records owned by the
// invoking user under the XDG state dir. Adapters are allow-listed with
// fixed argv builders: no arbitrary executable, shell string, or option
// injection is ever accepted, and no background service starts without a
// user submitting a job. Executing a job never overwrites existing
// output and never touches the source project file.
//
// Jobs run synchronously inside the invoking horneroctl process; there is
// no durable background worker. Cancelling therefore cannot kill a live
// subprocess: it is a persisted-state transition. A queued job that is
// cancelled never runs, and studio_job_run re-reads the persisted state
// before and after execution so a cancellation recorded by another
// horneroctl invocation is never silently overwritten by a stale
// succeeded/failed write. True process-group cancellation would require
// owning the child PID across invocations and is deliberately not claimed.

pub const studio_jobs_schema_version = 1

pub struct StudioJob {
pub mut:
	id           string
	adapter      string
	input        string
	output       string
	state        string // queued | running | succeeded | failed | cancelled | interrupted
	progress     int  = -1
	cancellable  bool = true
	created_unix i64
	updated_unix i64
}

pub fn studio_jobs_dir() string {
	override := os.getenv('HORNERO_STUDIO_JOBS_DIR')
	if override.len > 0 {
		return override
	}
	p := resolve_paths()
	return os.join_path(p.state_dir, 'hornero', 'studio-jobs')
}

fn studio_job_file(id string) string {
	return os.join_path(studio_jobs_dir(), '${id}.json')
}

fn studio_job_log_file(id string) string {
	return os.join_path(studio_jobs_dir(), '${id}.log')
}

pub const studio_adapter_ids = ['blender-render', 'ffmpeg-export', 'kdenlive-render', 'melt-render']

fn studio_video_output_ext_ok(output string) bool {
	return os.file_ext(output).to_lower() in ['.mp4', '.mkv', '.mov', '.webm']
}

// studio_adapter_argv is the allow-list. Each adapter validates its own
// inputs and returns a fixed argv (program separate from arguments).
// Paths beginning with '-' are refused for every adapter so a file name
// can never be re-interpreted as an option by the underlying tool.
pub fn studio_adapter_argv(adapter string, input string, output string) ![]string {
	if input.starts_with('-') || output.starts_with('-') {
		return error('studio job paths must not start with - (option injection guard)')
	}
	match adapter {
		'blender-render' {
			if !input.to_lower().ends_with('.blend') {
				return error('blender-render input must be a .blend file')
			}
			return ['blender', '-b', input, '-o', output, '-a']
		}
		'ffmpeg-export' {
			if !studio_video_output_ext_ok(output) {
				return error('ffmpeg-export output must end in .mp4, .mkv, .mov, or .webm')
			}
			return ['ffmpeg', '-hide_banner', '-nostdin', '-i', input, output]
		}
		'kdenlive-render' {
			// Renders a native Kdenlive project with Kdenlive itself
			// (default MP4-H264/AAC preset when none is named). The
			// .kdenlive source is opened read-only by the renderer.
			if !input.to_lower().ends_with('.kdenlive') {
				return error('kdenlive-render input must be a .kdenlive project file')
			}
			if !studio_video_output_ext_ok(output) {
				return error('kdenlive-render output must end in .mp4, .mkv, .mov, or .webm')
			}
			return ['kdenlive', '--render', input, output]
		}
		'melt-render' {
			// Renders MLT XML (a .kdenlive project is MLT XML) with the
			// melt engine, without needing the Kdenlive GUI stack.
			lower := input.to_lower()
			if !lower.ends_with('.kdenlive') && !lower.ends_with('.mlt') {
				return error('melt-render input must be a .kdenlive or .mlt file')
			}
			if !studio_video_output_ext_ok(output) {
				return error('melt-render output must end in .mp4, .mkv, .mov, or .webm')
			}
			return ['melt', input, '-consumer', 'avformat:${output}']
		}
		else {
			return error('unknown studio job adapter ${adapter} (valid: ${studio_adapter_ids.join(', ')})')
		}
	}
}

pub fn studio_validate_job_request(adapter string, input string, output string) ! {
	if adapter.len == 0 {
		return error('a studio job needs --adapter (${studio_adapter_ids.join(', ')})')
	}
	if input.len == 0 || output.len == 0 {
		return error('a studio job needs --input and --output paths')
	}
	if !os.is_file(input) {
		return error('input file does not exist: ${input}')
	}
	if os.abs_path(input) == os.abs_path(output) {
		return error('output must differ from the input file')
	}
	if os.exists(output) {
		return error('output already exists and is never overwritten: ${output}')
	}
	_ := studio_adapter_argv(adapter, input, output)!
}

fn studio_job_id(adapter string) string {
	return 'job-${time.now().unix_nano()}-${os.getpid()}-${adapter}'
}

pub fn studio_encode_job(job StudioJob) string {
	// String fields go through json2 encoding: interpolating raw paths
	// would emit invalid JSON for valid filenames containing quotes,
	// backslashes or control characters, breaking save/load round-trips.
	enc := fn (value string) string {
		return json2.encode(value, escape_unicode: true)
	}
	lines := [
		'{',
		'  "schemaVersion": ${studio_jobs_schema_version},',
		'  "id": ${enc(job.id)},',
		'  "adapter": ${enc(job.adapter)},',
		'  "input": ${enc(job.input)},',
		'  "output": ${enc(job.output)},',
		'  "state": ${enc(job.state)},',
		'  "progress": ${job.progress},',
		'  "cancellable": ${job.cancellable},',
		'  "createdUnix": ${job.created_unix},',
		'  "updatedUnix": ${job.updated_unix}',
		'}',
	]
	return lines.join('\n') + '\n'
}

pub fn studio_parse_job(raw string) !StudioJob {
	decoded := json2.decode[json2.Any](raw) or { return error('invalid JSON: ${err.msg()}') }
	if decoded !is map[string]json2.Any {
		return error('studio job must be a JSON object')
	}
	root := decoded.as_map()
	str_field := fn [root] (key string) !string {
		value := root[key] or { return error('studio job needs ${key}') }
		if value !is string {
			return error('${key} must be a string')
		}
		return value.str()
	}
	id := str_field('id')!
	adapter := str_field('adapter')!
	input := str_field('input')!
	output := str_field('output')!
	mut state := str_field('state')!
	if state !in ['queued', 'running', 'succeeded', 'failed', 'cancelled', 'interrupted'] {
		return error('unknown studio job state ${state}')
	}
	// A persisted "running" job has no live owner once this process is
	// reading it back: reconcile it to interrupted instead of lying.
	if state == 'running' {
		state = 'interrupted'
	}
	return StudioJob{
		id:           id
		adapter:      adapter
		input:        input
		output:       output
		state:        state
		progress:     (root['progress'] or { json2.Any(i64(-1)) }).int()
		cancellable:  true
		created_unix: (root['createdUnix'] or { json2.Any(i64(0)) }).i64()
		updated_unix: (root['updatedUnix'] or { json2.Any(i64(0)) }).i64()
	}
}

pub fn studio_save_job(job StudioJob) ! {
	dir := studio_jobs_dir()
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	path := studio_job_file(job.id)
	tmp := os.join_path(dir, '.${job.id}.tmp')
	os.write_file(tmp, studio_encode_job(job)) or {
		return error('cannot write ${tmp}: ${err.msg()}')
	}
	os.mv(tmp, path) or { return error('cannot move ${tmp} to ${path}: ${err.msg()}') }
}

pub fn studio_load_job(id string) !StudioJob {
	if id.len == 0 || id.contains('/') || id.contains('..') {
		return error('invalid studio job id')
	}
	path := studio_job_file(id)
	if !os.is_file(path) {
		return error('no such studio job: ${id}')
	}
	raw := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	return studio_parse_job(raw)!
}

pub fn studio_list_jobs() ![]StudioJob {
	dir := studio_jobs_dir()
	if !os.is_dir(dir) {
		return []StudioJob{}
	}
	mut jobs := []StudioJob{}
	for name in os.ls(dir) or { return error('cannot list ${dir}: ${err.msg()}') } {
		if !name.ends_with('.json') {
			continue
		}
		raw := os.read_file(os.join_path(dir, name)) or { continue }
		job := studio_parse_job(raw) or { continue }
		jobs << job
	}
	jobs.sort_with_compare(fn (a &StudioJob, b &StudioJob) int {
		if a.created_unix < b.created_unix {
			return -1
		}
		if a.created_unix > b.created_unix {
			return 1
		}
		return 0
	})
	return jobs
}

// studio_disk_free_bytes reports free bytes for a path's filesystem via a
// fixed df invocation, or none when unavailable. It never guesses.
pub fn studio_disk_free_bytes(path string) ?i64 {
	target := if os.is_dir(path) { path } else { os.dir(path) }
	rep := run_exec(ExecSpec{
		prog:        'df'
		args:        ['-B1', '--output=avail', target]
		timeout_sec: 5
	})
	if !rep.ok {
		return none
	}
	lines := rep.output.trim_space().split('\n')
	if lines.len < 2 {
		return none
	}
	return lines[lines.len - 1].trim_space().i64()
}

fn studio_job_data(job StudioJob) map[string]string {
	free := studio_disk_free_bytes(job.output)
	return {
		'id':          job.id
		'adapter':     job.adapter
		'input':       job.input
		'output':      job.output
		'state':       job.state
		'progress':    if job.progress >= 0 { '${job.progress}' } else { 'unknown' }
		'cancellable': '${job.cancellable}'
		'free_bytes':  if free != none { '${free}' } else { 'unknown' }
		'log':         studio_job_log_file(job.id)
	}
}

pub fn studio_job_submit_result(adapter string, input string, output string, execute bool, yes bool) CommandResult {
	studio_validate_job_request(adapter, input, output) or {
		return fail_result('studio jobs submit', err.msg())
	}
	if execute && !yes {
		return fail_result('studio jobs submit',
			'executing a job changes files; re-run with --execute --yes, or drop --execute to only queue it')
	}
	now := time.now().unix()
	mut job := StudioJob{
		id:           studio_job_id(adapter)
		adapter:      adapter
		input:        input
		output:       output
		state:        'queued'
		created_unix: now
		updated_unix: now
	}
	studio_save_job(job) or { return fail_result('studio jobs submit', err.msg()) }
	if !execute {
		return ok_result('studio jobs submit',
			'Queued ${job.id} (${adapter}): ${input} -> ${output}. Nothing ran yet; execute with: horneroctl studio jobs run ${job.id} --yes',
			studio_job_data(job))
	}
	return studio_job_run(job)
}

// studio_job_run executes one queued job synchronously with its fixed
// adapter argv, records a redaction-ready log, and reconciles state.
// The source input is opened read-only by the adapter; existing output
// is never overwritten (validated again immediately before running).
pub fn studio_job_run(job StudioJob) CommandResult {
	if job.state in ['succeeded', 'cancelled'] {
		return fail_result('studio jobs run', 'job ${job.id} already finished (${job.state})')
	}
	if os.exists(job.output) {
		mut failed := job
		failed.state = 'failed'
		failed.updated_unix = time.now().unix()
		studio_save_job(failed) or {}
		return fail_result('studio jobs run',
			'output already exists and is never overwritten: ${job.output} (job marked failed; fix the destination and resubmit)')
	}
	parent := os.dir(job.output)
	os.mkdir_all(parent) or {
		return fail_result('studio jobs run', 'cannot create output dir ${parent}: ${err.msg()}')
	}
	argv := studio_adapter_argv(job.adapter, job.input, job.output) or {
		return fail_result('studio jobs run', err.msg())
	}
	// A cancellation recorded after this job was loaded (by another
	// horneroctl invocation) wins over starting the subprocess. This
	// must be checked before persisting 'running', which would
	// otherwise overwrite the cancellation.
	fresh_pre := studio_load_job(job.id) or { job }
	if fresh_pre.state == 'cancelled' {
		return fail_result('studio jobs run',
			'job ${job.id} was cancelled before execution started; nothing ran and no output was written')
	}
	mut running := job
	running.state = 'running'
	running.updated_unix = time.now().unix()
	studio_save_job(running) or { return fail_result('studio jobs run', err.msg()) }
	rep := run_exec(ExecSpec{
		prog: argv[0]
		args: argv[1..]
	})
	os.write_file(studio_job_log_file(job.id), rep.output) or {}
	// Jobs run synchronously, so a cancellation recorded while the
	// subprocess ran cannot have stopped it; honour it in the final
	// state instead of overwriting it with a stale verdict.
	fresh_post := studio_load_job(job.id) or { running }
	if fresh_post.state == 'cancelled' {
		return ok_result('studio jobs run',
			'${job.id} was cancelled while running; the subprocess had already finished (exit ${rep.exit_code}) and any output at ${job.output} is not treated as a finished render. Cancellation is a state transition, not a process kill — see horneroctl studio jobs --help.',
			studio_job_data(fresh_post))
	}
	mut done := running
	done.state = if rep.ok { 'succeeded' } else { 'failed' }
	done.updated_unix = time.now().unix()
	studio_save_job(done) or { return fail_result('studio jobs run', err.msg()) }
	if rep.ok {
		return ok_result('studio jobs run',
			'${done.id} succeeded: ${job.input} -> ${job.output} (log: ${studio_job_log_file(job.id)}, redacted on read)',
			studio_job_data(done))
	}
	return fail_result('studio jobs run',
		'${done.id} failed (exit ${rep.exit_code}); partial output may exist at ${job.output} and is identified as partial — it is never treated as a finished render. See: horneroctl studio jobs log ${job.id}')
}

pub fn studio_job_run_result(id string, yes bool) CommandResult {
	if !yes {
		return fail_result('studio jobs run', 'running a job changes files; re-run with --yes')
	}
	job := studio_load_job(id) or { return fail_result('studio jobs run', err.msg()) }
	return studio_job_run(job)
}

pub fn studio_jobs_list_result() CommandResult {
	jobs := studio_list_jobs() or { return fail_result('studio jobs list', err.msg()) }
	if jobs.len == 0 {
		return ok_result('studio jobs list', 'No Studio jobs recorded yet.', {
			'count': '0'
		})
	}
	lines := jobs.map('${it.id}  ${it.state}  ${it.adapter}  ${it.input} -> ${it.output}')
	// Structured per-job rows for Shell consumers: tab-separated fields
	// under job_<n> keys (paths may contain commas/spaces, never tabs in
	// practice; ids/states/adapters are controlled vocabularies).
	mut data := {
		'count': '${jobs.len}'
	}
	for i, job in jobs {
		data['job_${i}'] = '${job.id}\t${job.state}\t${job.adapter}\t${job.input}\t${job.output}'
	}
	return ok_result('studio jobs list', lines.join('\n'), data)
}

pub fn studio_job_status_result(id string) CommandResult {
	job := studio_load_job(id) or { return fail_result('studio jobs status', err.msg()) }
	return ok_result('studio jobs status',
		'${job.id}: ${job.state} (${job.adapter}) ${job.input} -> ${job.output}',
		studio_job_data(job))
}

pub fn studio_job_cancel_result(id string) CommandResult {
	job := studio_load_job(id) or { return fail_result('studio jobs cancel', err.msg()) }
	if job.state in ['succeeded', 'failed', 'cancelled'] {
		return fail_result('studio jobs cancel', 'job ${id} already finished (${job.state})')
	}
	mut cancelled := job
	cancelled.state = 'cancelled'
	cancelled.updated_unix = time.now().unix()
	studio_save_job(cancelled) or { return fail_result('studio jobs cancel', err.msg()) }
	return ok_result('studio jobs cancel',
		'Cancelled ${id}. Jobs run synchronously, so this records a state transition (a queued job will never run; a job already executing in another invocation finishes its subprocess but keeps the cancelled state). No source file was touched; any partial output stays identified at ${job.output}.',
		studio_job_data(cancelled))
}

pub fn studio_job_log_result(id string) CommandResult {
	job := studio_load_job(id) or { return fail_result('studio jobs log', err.msg()) }
	_ := job
	path := studio_job_log_file(id)
	if !os.is_file(path) {
		return ok_result('studio jobs log', 'No log recorded for ${id} yet.', {
			'id':  id
			'log': path
		})
	}
	raw := os.read_file(path) or { return fail_result('studio jobs log', err.msg()) }
	// Logs are redacted on every read: adapter output can contain
	// credentials or stream keys and is never shown raw.
	return ok_result('studio jobs log', redact_secrets(raw), {
		'id':  id
		'log': path
	})
}
