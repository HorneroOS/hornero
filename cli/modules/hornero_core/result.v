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
		ok:      true
		message: message
		data:    data
	}
}

pub fn fail_result(command string, message string) CommandResult {
	return CommandResult{
		command: command
		ok:      false
		message: message
		data:    map[string]string{}
	}
}

// fail_result_data is fail_result that keeps a structured payload.
// Pending approval/clarification outcomes are failures for the exit
// code (nothing succeeded yet) but machine consumers (the shell
// Workbench) must still receive the run id, the pending kind and the
// redacted detail from `data`, never by parsing the message prose.
pub fn fail_result_data(command string, message string, data map[string]string) CommandResult {
	return CommandResult{
		command: command
		ok:      false
		message: message
		data:    data
	}
}
