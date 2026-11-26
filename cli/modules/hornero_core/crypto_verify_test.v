module hornero_core

import crypto.ed25519
import encoding.base64
import os

fn test_sha256_file_hex_and_verify() {
	tmp := os.join_path(os.temp_dir(), 'hornero_crypto_verify_test.txt')
	defer {
		os.rm(tmp) or {}
	}
	os.write_file(tmp, 'hornero-native-vlib') or { panic(err) }

	digest := sha256_file_hex(tmp) or { panic(err) }
	assert digest.len == 64
	assert (verify_file_sha256(tmp, digest.to_upper()) or { panic(err) }) == true
	assert (verify_file_sha256(tmp, '0'.repeat(64)) or { panic(err) }) == false
}

fn test_verify_ed25519_signature_b64() {
	pub_key, priv_key := ed25519.generate_key() or { panic(err) }
	payload := 'hornero-plugin-payload'.bytes()
	sig := ed25519.sign(priv_key, payload) or { panic(err) }

	pub_b64 := base64.encode(pub_key)
	sig_b64 := base64.encode(sig)

	assert (verify_ed25519_signature_b64(pub_b64, payload, sig_b64) or { panic(err) }) == true
	assert (verify_ed25519_signature_b64(pub_b64, 'tampered'.bytes(), sig_b64) or { panic(err) }) == false
}
