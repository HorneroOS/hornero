module hornero_core

// Redaction marker replacing credential-like values in doctor output.
pub const redacted_marker = '[redacted]'

// secret_key_markers are case-insensitive fragments. A KEY=VALUE (or
// KEY: VALUE) pair is redacted when its key contains one of these.
const secret_key_markers = ['token', 'secret', 'password', 'passwd', 'pwd', 'key', 'auth', 'credential',
	'bearer']!

fn key_is_secret(key string) bool {
	lk := key.to_lower()
	for m in secret_key_markers {
		if lk.contains(m) {
			return true
		}
	}
	return false
}

fn is_key_char(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
		|| c == `_` || c == `-` || c == `.`
}

fn is_blank(c u8) bool {
	return c == ` ` || c == `\t`
}

fn is_value_end(c u8, to_eol bool) bool {
	if c == `\n` || c == `,` || c == `;` {
		return true
	}
	return !to_eol && is_blank(c)
}

// redact_around masks the value after every `sep` whose left-hand key looks
// secret-like. `=` values end at whitespace; `:` values run to end of line,
// so `Authorization: Bearer <token>` is fully masked.
fn redact_around(s string, sep u8) string {
	mut out := ''
	mut i := 0
	mut kept := 0
	for i < s.len {
		if s[i] != sep {
			i++
			continue
		}
		mut j := i - 1
		for j >= 0 && is_blank(s[j]) {
			j--
		}
		mut k := j
		for k >= 0 && is_key_char(s[k]) {
			k--
		}
		key := if j >= 0 && k < j { s[k + 1..j + 1] } else { '' }
		if key == '' || !key_is_secret(key) {
			i++
			continue
		}
		mut m := i + 1
		for m < s.len && is_blank(s[m]) {
			m++
		}
		if m >= s.len {
			i++
			continue
		}
		mut end := m
		if s[m] == `"` || s[m] == `'` {
			q := s[m]
			end = m + 1
			for end < s.len && s[end] != q {
				end++
			}
			if end < s.len {
				end++
			}
		} else {
			to_eol := sep == `:`
			for end < s.len && !is_value_end(s[end], to_eol) {
				end++
			}
		}
		if end == m {
			i++
			continue
		}
		out += s[kept..m] + redacted_marker
		kept = end
		i = end
	}
	out += s[kept..]
	return out
}

// redact_secrets masks credential-like KEY=VALUE shapes (tokens, keys,
// passwords) so doctor output never prints secrets verbatim.
pub fn redact_secrets(s string) string {
	if s == '' {
		return s
	}
	return redact_around(redact_around(s, `=`), `:`)
}
