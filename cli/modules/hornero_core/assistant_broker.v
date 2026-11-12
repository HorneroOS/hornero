module hornero_core

import os
import time

// -- Typed capability broker -------------------------------------------------
// The broker is the only path from an agent request to a host effect. It
// exposes a fixed catalogue of typed tools (never a generic command
// endpoint), evaluates each call through the ABAC policy, executes the
// allowlisted literal argv outside Hermes, and writes an audit line.
// Callers: the trusted shell/user via `horneroctl assistant tool`. The
// agent inside the sandbox cannot reach this code path with policy-writing
// authority: the policy file and the broker's approval flag live outside
// the sandbox bind set.

pub struct AssistantBrokerTool {
pub:
	name     string
	action   string
	mutating bool
}

// assistant_broker_catalogue is exhaustive: anything not listed here does
// not exist as far as the agent is concerned.
pub fn assistant_broker_catalogue() []AssistantBrokerTool {
	return [
		AssistantBrokerTool{'system_info', 'desktop.observe', false},
		AssistantBrokerTool{'appearance_status', 'desktop.observe', false},
		AssistantBrokerTool{'theme_list', 'desktop.observe', false},
		AssistantBrokerTool{'theme_show', 'desktop.observe', false},
		AssistantBrokerTool{'gtk_list', 'desktop.observe', false},
		AssistantBrokerTool{'gtk_current', 'desktop.observe', false},
		AssistantBrokerTool{'package_updates', 'desktop.observe', false},
		AssistantBrokerTool{'window_list', 'desktop.window.list', false},
		AssistantBrokerTool{'theme_set', 'appearance.modify', true},
		AssistantBrokerTool{'window_focus', 'desktop.window.focus', true},
		AssistantBrokerTool{'notify', 'notifications.send', true},
		AssistantBrokerTool{'screenshot', 'desktop.screenshot', true},
	]
}

pub fn assistant_broker_tool(name string) (AssistantBrokerTool, bool) {
	for t in assistant_broker_catalogue() {
		if t.name == name {
			return t, true
		}
	}
	return AssistantBrokerTool{}, false
}

// assistant_broker_argv returns literal argv for a tool, or an error for
// anything outside the catalogue or with unsafe arguments.
pub fn assistant_broker_argv(tool string, arg string) ![]string {
	match tool {
		'screenshot' {
			return ['grim', '<workspace>/screenshot-<timestamp>.png']
		}
		'theme_set' {
			if arg !in ['hornero-dark', 'hornero-light', 'pampa'] {
				return error('theme_set needs an official theme id (hornero-dark, hornero-light, pampa)')
			}
			return ['horneroctl', 'appearance', 'theme', 'set', arg, '--yes']
		}
		'window_list' {
			return ['hyprctl', 'clients', '-j']
		}
		'window_focus' {
			if arg.len < 3 || !arg.starts_with('0x') {
				return error('window_focus needs a window address like 0x1234abcd')
			}
			for ch in arg[2..] {
				if !ch.is_digit() && !(ch >= `a` && ch <= `f`) {
					return error('window_focus address must be hex')
				}
			}
			return ['hyprctl', 'dispatch', 'focuswindow', 'address:${arg}']
		}
		'notify' {
			if arg.len == 0 || arg.len > 200 {
				return error('notify needs text (1-200 chars)')
			}
			return ['notify-send', 'Javi', arg]
		}
		else {
			// Read-only slice-1 tools keep their existing allowlist.
			return assistant_tool_argv(tool, arg)
		}
	}
}

fn assistant_broker_resource(tool string, arg string) string {
	match tool {
		'screenshot' { return 'workspace' }
		'theme_set', 'window_focus' { return arg }
		'notify' { return 'local' }
		else { return 'any' }
	}
}

// assistant_broker_exec_report evaluates policy, then executes. When the
// policy requires approval, `approved_once` (the human's --yes at this
// trusted CLI) satisfies exactly this one call and is audit-logged; it is
// never persisted as a standing grant.
pub fn assistant_broker_exec_report(tool string, arg string, mode string, approved_once bool, dry_run bool) CommandResult {
	spec_tool, found := assistant_broker_tool(tool)
	if !found {
		assistant_log_append('tool.${tool}', '', arg, 'deny:unknown-tool')
		return fail_result('assistant tool', 'Unknown tool "${tool}". List tools with: horneroctl assistant tools')
	}
	argv := assistant_broker_argv(tool, arg) or {
		return fail_result('assistant tool', err.msg())
	}
	rules, _ := assistant_policy_load()
	resource := assistant_broker_resource(tool, arg)
	mut req := AssistantPolicyRequest{
		principal:      'javi.main'
		action:         spec_tool.action
		resource:       resource
		workspace_root: assistant_workspace_active().root
		mode:           if mode.len > 0 { mode } else { 'agent' }
		interactive:    true
		now:            time.now().unix()
	}
	if approved_once {
		req = AssistantPolicyRequest{
			...req
			approval_id:     'cli-once'
			approval_action: spec_tool.action
			approval_target: resource
			approval_exp:    req.now + 60
		}
	}
	decision := assistant_policy_decide(rules, req)
	if decision.decision != 'allow' {
		assistant_log_append('tool.${tool}', '', '${spec_tool.action} ${resource}',
			decision.decision)
		return CommandResult{
			command: 'assistant tool'
			ok:      false
			message: 'Policy ${decision.decision}: ${decision.reason}. Nothing executed. If this is a legitimate action, approve it interactively or adjust the preset in Control Center > Javi > Permissions.'
			data:    {
				'decision': decision.decision
				'action':   spec_tool.action
				'resource': resource
			}
		}
	}
	if tool == 'screenshot' {
		ws := assistant_workspace_active().root
		os.mkdir_all(ws) or {}
		target := os.join_path(ws, 'screenshot-${time.now().custom_format('YYYYMMDDHHmmss')}.png')
		if dry_run {
			return ok_result('assistant tool', 'Dry run (policy allow): would capture the screen to ${target} via grim on the trusted side. The agent process itself has no compositor access.', {
				'dryRun':   'true'
				'decision': 'allow'
				'target':   target
			})
		}
		rep := run_exec(ExecSpec{
			prog:        'grim'
			args:        [target]
			timeout_sec: 30
		})
		status := if rep.ok { 'ok' } else { 'error:${rep.exit_code}' }
		assistant_log_append('tool.screenshot', '', target, status)
		if !rep.ok {
			return fail_result('assistant tool', 'Screenshot failed (compositor access outside the agent sandbox): ${rep.output}')
		}
		return ok_result('assistant tool', 'Screenshot saved inside the active workspace: ${target}', {
			'tool':     tool
			'action':   spec_tool.action
			'decision': 'allow'
			'target':   target
			'audited':  'true'
		})
	}
	if dry_run {
		return ok_result('assistant tool', 'Dry run (policy allow): would run: ${argv.join(' ')}', {
			'dryRun':   'true'
			'decision': 'allow'
		})
	}
	rep := run_exec(ExecSpec{
		prog:        argv[0]
		args:        argv[1..]
		timeout_sec: 60
	})
	status := if rep.ok { 'ok' } else { 'error:${rep.exit_code}' }
	assistant_log_append('tool.${tool}', '', '${spec_tool.action} ${resource}', status)
	if !rep.ok {
		return fail_result('assistant tool', '${tool} failed: ${rep.output}')
	}
	out := if rep.output.len > 4000 { rep.output[..4000] } else { rep.output }
	return ok_result('assistant tool', out, {
		'tool':     tool
		'action':   spec_tool.action
		'decision': 'allow'
		'audited':  'true'
	})
}

pub fn assistant_broker_tools_report() CommandResult {
	mut lines := ['Read-only and mediated tools the assistant may call through the broker (policy-gated, audited):']
	for t in assistant_broker_catalogue() {
		argv := assistant_broker_argv(t.name, 'example') or {
			['(needs a valid argument)']
		}
		_ = argv
		lines << '${t.name}  [${t.action}${if t.mutating { ', mediated' } else { '' }}]'
	}
	lines << 'Anything not listed cannot be invoked. There is no generic command tool.'
	return ok_result('assistant tools', lines.join('\n'), {
		'class': 'broker-typed'
		'count': assistant_broker_catalogue().len.str()
	})
}
