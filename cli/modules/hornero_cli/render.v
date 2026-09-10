module hornero_cli

import hornero_core
import json2

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
			println(json2.encode({
				'ok':      'false'
				'code':    err.code
				'message': err.message
			}, escape_unicode: true))
		}
		.human {
			eprintln(err.message)
		}
	}
	return err.exit_code()
}
