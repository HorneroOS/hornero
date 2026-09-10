module hornero_core

// RenderMode selects the output shape. Global flags: --json, --quiet.
pub enum RenderMode {
	human
	json
	quiet
}

// CommandResult is the single success envelope every command returns.
// Core never prints; the cli adapter renders this value.
pub struct CommandResult {
pub:
	command string
	ok      bool
	message string
	data    map[string]string
}

pub fn ok_result(command string, message string, data map[string]string) CommandResult {
	return CommandResult{
		command: command
		ok: true
		message: message
		data: data
	}
}

pub fn fail_result(command string, message string) CommandResult {
	return CommandResult{
		command: command
		ok: false
		message: message
		data: map[string]string{}
	}
}
