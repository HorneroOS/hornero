module hornero_cli

import hornero_core
import x.json2

// render writes a CommandResult to stdout per mode and returns the exit code.
pub fn render(result hornero_core.CommandResult, mode hornero_core.RenderMode) int {
	match mode {
		.quiet {
			if result.ok {
				return 0
			}
			return hornero_core.err_user('command.failed', result.message).exit_code()
		}
		.json {
			println(json2.encode(result, escape_unicode: true))
			if result.ok {
				return 0
			}
			return hornero_core.err_user('command.failed', result.message).exit_code()
		}
		.human {
			println(result.message)
			if result.ok {
				return 0
			}
			return hornero_core.err_user('command.failed', result.message).exit_code()
		}
	}
}

// render_error prints a domain error per mode and returns its exit code.
pub fn render_error(err hornero_core.DomainError, mode hornero_core.RenderMode) int {
	match mode {
		.quiet {}
		.json {
			println(error_json(err))
		}
		.human {
			eprintln(err.message)
		}
	}
	return err.exit_code()
}

// error_json keeps error envelopes aligned with the typed JSON success
// envelope: `ok` is a JSON boolean, not the string "false".
pub fn error_json(err hornero_core.DomainError) string {
	return json2.encode({
		'ok':      json2.Any(false)
		'code':    json2.Any(err.code)
		'message': json2.Any(err.message)
	},
		escape_unicode: true
	)
}
