module hornero_cli

import hornero_core
import os

// run_assistant_approve adds the CLI half of the user-presence proof:
// when an approve needs presence and no --presence token was given, an
// interactive terminal (stdin and stdout TTYs, human output) shows the
// pending request and asks the user to type `approve`. The answer is
// bound to the request it showed. This is the only prompt in
// horneroctl and it never appears for non-interactive callers, which
// fail fast instead (CLI contract: automation never blocks on input).
fn run_assistant_approve(opts AssistantCmdOptions, mode hornero_core.RenderMode) int {
	mut presence := hornero_core.AssistantApprovalPresence{
		token: opts.presence
	}
	mut request := opts.request
	if approve_wants_tty_confirmation(opts, mode, os.is_atty(0) == 1 && os.is_atty(1) == 1) {
		ctl := hornero_core.assistant_pending_approval_control(opts.arg1)
		// Only the text the gateway binds to this request id is shown.
		shown := if ctl.detail.len > 0 {
			ctl.detail
		} else {
			'an action the gateway did not describe (deny unless you expected it)'
		}
		ref := if ctl.found { hornero_core.assistant_request_ref(ctl) } else { '' }
		println_human('Run ${opts.arg1} asks to: ${hornero_core.assistant_redact_tokens(shown)}')
		if ref.len > 0 {
			println_human('Request ${ref}.')
		}
		print('Type approve to allow it once (anything else cancels): ')
		flush_stdout()
		answer := os.get_line().trim_space()
		if answer != 'approve' {
			return render(hornero_core.fail_result('assistant approve', 'Not approved; nothing was decided.'),
				mode)
		}
		presence = hornero_core.AssistantApprovalPresence{
			tty_confirmed: true
		}
		if request.len == 0 {
			request = ref
		}
	}
	return render(hornero_core.assistant_approve_report_presence(opts.arg1, opts.arg2, request,
		presence), mode)
}

// approve_wants_tty_confirmation is pure for tests.
fn approve_wants_tty_confirmation(opts AssistantCmdOptions, mode hornero_core.RenderMode, interactive bool) bool {
	return opts.arg2 == 'approve' && opts.presence.len == 0 && mode == .human && interactive
		&& hornero_core.assistant_load_settings().require_presence
}
