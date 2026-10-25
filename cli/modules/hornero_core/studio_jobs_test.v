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
