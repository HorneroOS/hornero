module hornero_core

import os

// Microphone backend: PipeWire source mute state via wpctl, mirroring
// dots-microphone. The event-driven listen loop (status-bar tail) stays
// in the dots-microphone shim; horneroctl owns single-shot status plus
// the gated toggle.

// resolve_wpctl_bin locates wpctl. Override with HORNERO_WPCTL_BIN.
pub fn resolve_wpctl_bin() string {
	env := os.getenv('HORNERO_WPCTL_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('wpctl')
}

// mic_source returns the PipeWire source id: HORNERO_MIC_SOURCE, else the
// wpctl default-source placeholder (no `wpctl status` + pw-cli parsing
// needed on recent WirePlumber).
fn mic_source() string {
	env := os.getenv('HORNERO_MIC_SOURCE')
	if env.len > 0 {
		return env
	}
	return '@DEFAULT_AUDIO_SOURCE@'
}

pub struct MicStatusOptions {
pub:
	dry_run bool
}

// mic_status_report implements `hardware mic status` (read-only): muted
// or unmuted plus the raw wpctl reading.
pub fn mic_status_report(opts MicStatusOptions) CommandResult {
	src := mic_source()
	bin := resolve_wpctl_bin()
	if opts.dry_run {
		prog := if bin.len > 0 { bin } else { 'wpctl' }
		return ok_result('hardware mic status', 'would run: ${command_line(prog, [
			'get-volume',
			src,
		])}', {
			'command_line': command_line(prog, ['get-volume', src])
			'dry_run':      'true'
		})
	}
	if bin.len == 0 {
		return fail_result('hardware mic status', 'wpctl not found on PATH. Set HORNERO_WPCTL_BIN.\nExample: horneroctl hardware mic status --dry-run')
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['get-volume', src]
	})
	if !rep.ok {
		return fail_result('hardware mic status', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	state := if rep.output.contains('MUTED') { 'muted' } else { 'unmuted' }
	return ok_result('hardware mic status', '${state} (${rep.output.trim_space()})', {
		'state':  state
		'source': src
		'detail': rep.output.trim_space()
	})
}

pub struct MicToggleOptions {
pub:
	dry_run bool
	yes     bool
}

// mic_toggle_report implements `hardware mic toggle` via
// `wpctl set-mute <source> toggle`. Mutating: needs --yes; --dry-run
// only previews.
pub fn mic_toggle_report(opts MicToggleOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('hardware mic toggle', 'refusing to toggle the microphone without --yes (preview with --dry-run).\nExample: horneroctl hardware mic toggle --dry-run')
	}
	src := mic_source()
	bin := resolve_wpctl_bin()
	if bin.len == 0 {
		if opts.dry_run {
			return ok_result('hardware mic toggle', 'would run: wpctl set-mute ${src} toggle',
				{
					'command_line': 'wpctl set-mute ${src} toggle'
					'dry_run':      'true'
				})
		}
		return fail_result('hardware mic toggle', 'wpctl not found on PATH. Set HORNERO_WPCTL_BIN.\nExample: horneroctl hardware mic toggle --dry-run')
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    ['set-mute', src, 'toggle']
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('hardware mic toggle', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('hardware mic toggle', 'microphone toggled', {
			'command_line': rep.command_line
		})
	}
	return fail_result('hardware mic toggle', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
