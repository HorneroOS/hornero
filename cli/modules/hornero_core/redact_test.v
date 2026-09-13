module hornero_core

import os

fn test_redact_key_value_shapes() {
	assert redact_secrets('api_token=abc123') == 'api_token=${redacted_marker}'
	assert redact_secrets('DB_PASSWORD=hunter2') == 'DB_PASSWORD=${redacted_marker}'
	assert redact_secrets('auth_token="abc 123" trailing') == 'auth_token=${redacted_marker} trailing'
	assert redact_secrets("api_secret='s3cr3t' ok") == 'api_secret=${redacted_marker} ok'
	assert redact_secrets('Authorization: Bearer abc123') == 'Authorization: ${redacted_marker}'
	assert redact_secrets('api_key: abc123, region: us') == 'api_key: ${redacted_marker}, region: us'
	// Non-secret pairs and plain prose pass through untouched.
	assert redact_secrets('WAYLAND_DISPLAY=wayland-1') == 'WAYLAND_DISPLAY=wayland-1'
	assert redact_secrets('qs not found on PATH') == 'qs not found on PATH'
	assert redact_secrets('HYPRLAND_INSTANCE_SIGNATURE is not set') == 'HYPRLAND_INSTANCE_SIGNATURE is not set'
	assert redact_secrets('') == ''
}

fn test_doctor_result_never_prints_env_secret_verbatim() {
	secret := 'hx-test-token-9f8e7d6c5b4a'
	os.setenv('HORNERO_TEST_API_TOKEN', secret, true)
	leaked := os.getenv('HORNERO_TEST_API_TOKEN')
	checks := [
		DoctorCheck{
			name:   'env-derived'
			ok:     true
			detail: 'HORNERO_TEST_API_TOKEN=${leaked}'
		},
		DoctorCheck{
			name:   'password-leak'
			ok:     false
			detail: 'login failed for DB_PASSWORD=${leaked}'
		},
	]
	r := doctor_result(checks)
	assert r.command == 'doctor'
	assert !r.ok
	assert !r.message.contains(secret)
	assert r.message.contains(redacted_marker)
	assert r.data['env-derived'] == 'ok'
	assert r.data['password-leak'] == 'fail'
	os.unsetenv('HORNERO_TEST_API_TOKEN')
}
