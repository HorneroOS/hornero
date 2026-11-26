module hornero_core

import crypto.ed25519
import crypto.sha256
import encoding.base64
import encoding.hex
import os

// sha256_file_hex computes the lowercase hex SHA-256 digest of a file using native vlib.
pub fn sha256_file_hex(path string) !string {
	data := os.read_bytes(path) or { return error('cannot read ${path}: ${err.msg()}') }
	digest := sha256.sum(data)
	return hex.encode(digest)
}

// verify_file_sha256 verifies a file's SHA-256 digest against an expected hex string
// (case-insensitive, whitespace-trimmed) with zero external shell-outs.
pub fn verify_file_sha256(path string, expected_hex string) !bool {
	want := expected_hex.trim_space().to_lower()
	if want.len != 64 {
		return error('invalid sha256 hex length: expected 64, got ${want.len}')
	}
	got := sha256_file_hex(path)!
	return got == want
}

// verify_ed25519_signature_b64 verifies a base64-encoded Ed25519 signature over payload
// against a base64-encoded 32-byte Ed25519 public key using native `crypto.ed25519`.
pub fn verify_ed25519_signature_b64(pubkey_b64 string, payload []u8, sig_b64 string) !bool {
	pub_bytes := base64.decode(pubkey_b64.trim_space())
	if pub_bytes.len != ed25519.public_key_size {
		return error('invalid ed25519 public key length: ${pub_bytes.len}')
	}
	sig_bytes := base64.decode(sig_b64.trim_space())
	if sig_bytes.len != ed25519.signature_size {
		return error('invalid ed25519 signature length: ${sig_bytes.len}')
	}
	pub_key := ed25519.PublicKey(pub_bytes)
	return ed25519.verify(pub_key, payload, sig_bytes)
}
