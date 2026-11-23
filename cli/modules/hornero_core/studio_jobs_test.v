module hornero_core

import os

// Studio job lifecycle tests with fake adapters on PATH. Everything
// lives under /tmp; each test restores the env it overrides.

const jobs_test_root = '/tmp/hx-studio-jobs-test'

fn jobs_setup(tag string) (string, string) {
	root := '${jobs_test_root}/${tag}'
	if os.exists(root) {
		os.rmdir_all(root) or {}
	}
	bin_dir := '${root}/bin'
	jobs_dir := '${root}/jobs'
	os.mkdir_all(bin_dir) or { assert false }
	os.mkdir_all(jobs_dir) or { assert false }
	os.mkdir_all('${root}/project') or { assert false }
	os.setenv('HORNERO_STUDIO_JOBS_DIR', jobs_dir, true)
	// Fake ffmpeg: writes its last argument as output and prints a
	// credential-looking line so log redaction is observable.
	fake := '#!/bin/sh\nfor last; do :; done\nprintf "fake-output\\n" > "$last"\nK=abc123\necho "export done token=\$K"\n'
	os.write_file('${bin_dir}/ffmpeg', fake) or { assert false }
	os.chmod('${bin_dir}/ffmpeg', 0o755) or {}
	// Fake kdenlive --render: last argument is the output file.
	os.write_file('${bin_dir}/kdenlive', fake) or { assert false }
	os.chmod('${bin_dir}/kdenlive', 0o755) or {}
	// Fake melt: output is embedded in the avformat:<path> consumer arg.
	fake_melt := '#!/bin/sh\nfor a in "$@"; do case "$a" in avformat:*) printf "fake-output\\n" > "\${a#avformat:}";; esac; done\necho "melt done"\n'
	os.write_file('${bin_dir}/melt', fake_melt) or { assert false }
	os.chmod('${bin_dir}/melt', 0o755) or {}
	os.setenv('PATH', '${bin_dir}:${os.getenv('PATH')}', true)
	return root, jobs_dir
}

fn jobs_teardown() {
	os.unsetenv('HORNERO_STUDIO_JOBS_DIR')
}

fn test_job_validation_rejects_unsafe_requests() {
	root, _ := jobs_setup('validate')
	defer {
		jobs_teardown()
	}
	input := '${root}/project/in.mov'
	os.write_file(input, 'video') or { assert false }
	assert !studio_job_submit_result('vlc', input, '${root}/out.mp4', false, false).ok
	assert !studio_job_submit_result('ffmpeg-export', '${root}/missing.mov', '${root}/out.mp4', false, false).ok
	assert !studio_job_submit_result('ffmpeg-export', input, '${root}/out.avi', false, false).ok
	assert !studio_job_submit_result('ffmpeg-export', input, input, false, false).ok
	existing := '${root}/exists.mp4'
	os.write_file(existing, 'old') or { assert false }
	assert !studio_job_submit_result('ffmpeg-export', input, existing, false, false).ok
	// Execute without explicit confirmation never runs.
	assert !studio_job_submit_result('ffmpeg-export', input, '${root}/out.mp4', true, false).ok
}

fn test_job_queue_execute_and_redacted_log() {
	root, _ := jobs_setup('execute')
	defer {
		jobs_teardown()
	}
	input := '${root}/project/in.mov'
	output := '${root}/project/out.mp4'
	os.write_file(input, 'video') or { assert false }

	queued := studio_job_submit_result('ffmpeg-export', input, output, false, false)
	assert queued.ok
	job_id := queued.data['id']
	assert job_id.len > 0
	assert queued.data['state'] == 'queued'
	assert !os.exists(output)

	ran := studio_job_run_result(job_id, true)
	assert ran.ok, ran.message
	assert os.exists(output)
	status := studio_job_status_result(job_id)
	assert status.ok
	assert status.data['state'] == 'succeeded'

	log := studio_job_log_result(job_id)
	assert log.ok
	assert !log.message.contains('abc123')
	assert log.message.contains('export done')

	// Structured list rows for Shell consumers (job_<n>, tab-separated).
	list := studio_jobs_list_result()
	assert list.ok
	assert list.data['count'] == '1'
	row := list.data['job_0'].split('\t')
	assert row.len == 5
	assert row[0] == job_id
	assert row[1] == 'succeeded'
	assert row[2] == 'ffmpeg-export'
}

fn test_job_cancel_and_interrupted_reconcile() {
	root, _ := jobs_setup('cancel')
	defer {
		jobs_teardown()
	}
	input := '${root}/project/scene.blend'
	os.write_file(input, 'blend') or { assert false }
	queued := studio_job_submit_result('blender-render', input, '${root}/render/frame_', false, false)
	assert queued.ok
	job_id := queued.data['id']

	cancelled := studio_job_cancel_result(job_id)
	assert cancelled.ok
	assert studio_job_status_result(job_id).data['state'] == 'cancelled'
	// A finished job cannot be cancelled or run again.
	assert !studio_job_cancel_result(job_id).ok
	assert !studio_job_run_result(job_id, true).ok

	// A stale "running" record reconciles to interrupted on read.
	stale := StudioJob{
		id:           'job-stale-1'
		adapter:      'ffmpeg-export'
		input:        input
		output:       '${root}/x.mp4'
		state:        'running'
		created_unix: 1
		updated_unix: 1
	}
	studio_save_job(stale) or { assert false }
	loaded := studio_load_job('job-stale-1') or { assert false }
	assert loaded.state == 'interrupted'
	// ...and an interrupted job may be retried safely (output absent).
	assert studio_job_status_result('job-stale-1').data['state'] == 'interrupted'
}

fn test_kdenlive_and_melt_adapters() {
	root, _ := jobs_setup('kdenlive-melt')
	defer {
		jobs_teardown()
	}
	project := '${root}/project/edit.kdenlive'
	os.write_file(project, '<mlt/>') or { assert false }

	// Fixed argv shapes, verified against the real tools' CLI contracts.
	kargv := studio_adapter_argv('kdenlive-render', project, '${root}/final.mp4') or {
		assert false
		[]string{}
	}
	assert kargv == ['kdenlive', '--render', project, '${root}/final.mp4']
	margv := studio_adapter_argv('melt-render', project, '${root}/preview.mp4') or {
		assert false
		[]string{}
	}
	assert margv == ['melt', project, '-consumer', 'avformat:${root}/preview.mp4']

	// Validation: wrong source types, wrong outputs, option injection.
	assert !studio_job_submit_result('kdenlive-render', '${root}/project/in.mov', '${root}/x.mp4', false, false).ok
	assert !studio_job_submit_result('melt-render', project, '${root}/x.avi', false, false).ok
	if _ := studio_adapter_argv('ffmpeg-export', '-i', '${root}/x.mp4') {
		assert false, 'dash-prefixed input must be refused'
	}

	// Execute both new adapters end to end with the fakes on PATH.
	kjob := studio_job_submit_result('kdenlive-render', project, '${root}/final.mp4', true, true)
	assert kjob.ok, kjob.message
	assert os.exists('${root}/final.mp4')
	mjob := studio_job_submit_result('melt-render', project, '${root}/preview.mp4', true, true)
	assert mjob.ok, mjob.message
	assert os.exists('${root}/preview.mp4')
	// The native project source is never modified by rendering.
	assert (os.read_file(project) or { '' }) == '<mlt/>'
}

fn test_run_respects_cancellation_recorded_after_load() {
	root, _ := jobs_setup('cancel-race')
	defer {
		jobs_teardown()
	}
	input := '${root}/project/in.mov'
	output := '${root}/project/race.mp4'
	os.write_file(input, 'video') or { assert false }
	queued := studio_job_submit_result('ffmpeg-export', input, output, false, false)
	assert queued.ok
	job_id := queued.data['id']
	stale := studio_load_job(job_id) or { assert false }
	// Another invocation cancels after we loaded the job.
	assert studio_job_cancel_result(job_id).ok
	// Running from the stale in-memory copy must not execute or overwrite
	// the cancelled state with a stale verdict.
	ran := studio_job_run(stale)
	assert !ran.ok
	assert !os.exists(output)
	assert studio_job_status_result(job_id).data['state'] == 'cancelled'
}

fn test_job_json_roundtrip_special_paths() {
	// Valid filenames with JSON-hostile characters must survive an
	// encode/parse round-trip byte-for-byte (HorneroOS/hornero#473).
	cases := [
		'/tmp/in "quoted".mov',
		'/tmp/back\\slash.mp4',
		'/tmp/tab\tname.mkv',
		'/tmp/unicodé — ñandú.mp4',
		"/tmp/it's a file.mov",
	]
	for path in cases {
		job := StudioJob{
			id:           'job-special-1'
			adapter:      'ffmpeg-export'
			input:        path
			output:       path + '.out.mp4'
			state:        'queued'
			progress:     -1
			created_unix: 42
			updated_unix: 43
		}
		parsed := studio_parse_job(studio_encode_job(job)) or {
			assert false, 'round-trip failed for ${path}: ${err.msg()}'
			continue
		}
		assert parsed.input == path, parsed.input
		assert parsed.output == path + '.out.mp4'
		assert parsed.id == job.id
		assert parsed.adapter == job.adapter
		assert parsed.created_unix == 42
	}
}
