module hornero_core

import os

// OS recovery readiness (hornero#179). This is diagnostics only: it
// probes whether the installed layout could host the contracted
// Btrfs/snapper backend and reports the shipped backend name from
// packages.v. It never creates, lists-as-restorable, or restores
// snapshots, and it must never be conflated with the configuration
// snapshots in snapshots.v, which are settings archives.

// RecoveryProbe is one read-only snapshot of recovery-relevant facts.
// recovery_doctor_checks is pure over it, mirroring the Bluetooth
// doctor, so every readiness claim is unit-testable without a real
// install.
pub struct RecoveryProbe {
pub mut:
	backend             string
	root_fstype         string
	snapshots_mounted   bool
	snapper_bin         string
	snapper_config      bool
	timeline_timer_unit bool
	cleanup_timer_unit  bool
}

// parse_mounts extracts the root filesystem type and whether the
// top-level snapshot store is mounted at /.snapshots from
// /proc/mounts content.
fn parse_mounts(content string) (string, bool) {
	mut fstype := ''
	mut store := false
	for line in content.split_into_lines() {
		fields := line.fields()
		if fields.len < 3 {
			continue
		}
		if fields[1] == '/' {
			fstype = fields[2]
		}
		if fields[1] == '/.snapshots' {
			store = true
		}
	}
	return fstype, store
}

fn recovery_probe() RecoveryProbe {
	mounts := os.read_file('/proc/mounts') or { '' }
	fstype, store := parse_mounts(mounts)
	return RecoveryProbe{
		backend:             snapshot_backend_name
		root_fstype:         fstype
		snapshots_mounted:   store
		snapper_bin:         find_on_path('snapper')
		snapper_config:      os.is_file('/etc/snapper/configs/root')
		timeline_timer_unit: os.is_file('/usr/lib/systemd/system/snapper-timeline.timer')
		cleanup_timer_unit:  os.is_file('/usr/lib/systemd/system/snapper-cleanup.timer')
	}
}

// recovery_doctor_checks maps a probe to readiness checks. Every
// check reports detection only: presence of a layout, a binary, or a
// config file is not proof that a restore works - that proof is the
// disposable-VM acceptance in the snapshot backend contract.
pub fn recovery_doctor_checks(probe RecoveryProbe) []DoctorCheck {
	mut checks := []DoctorCheck{}
	checks << DoctorCheck{
		name:   'snapshot-backend'
		ok:     probe.backend != 'none' && probe.backend.len > 0
		detail: if probe.backend == 'none' || probe.backend.len == 0 {
			snapshot_unavailable_status
		} else {
			'backend: ${probe.backend} (readiness probes are not proof of a validated restore)'
		}
	}
	checks << DoctorCheck{
		name:   'root-filesystem'
		ok:     probe.root_fstype == 'btrfs'
		detail: if probe.root_fstype == 'btrfs' {
			'root is btrfs (required by the contracted snapshot backend)'
		} else if probe.root_fstype.len == 0 {
			'root filesystem type could not be determined from /proc/mounts; snapshot backend unsupported until probed'
		} else {
			'root is ${probe.root_fstype}; the Btrfs snapshot backend is unsupported on non-Btrfs installs'
		}
	}
	checks << DoctorCheck{
		name:   'snapshots-store'
		ok:     probe.snapshots_mounted
		detail: if probe.snapshots_mounted {
			'/.snapshots is mounted (top-level snapshot store, outside the root subvolume)'
		} else {
			'no /.snapshots mount; fresh Btrfs installs provide the top-level store and existing installs are not migrated automatically'
		}
	}
	checks << DoctorCheck{
		name:   'snapper'
		ok:     probe.snapper_bin.len > 0
		detail: if probe.snapper_bin.len > 0 {
			probe.snapper_bin
		} else {
			'snapper not found on PATH; it ships only with the opt-in snapshots capability'
		}
	}
	checks << DoctorCheck{
		name:   'snapper-config'
		ok:     probe.snapper_config
		detail: if probe.snapper_config {
			'/etc/snapper/configs/root present (a config file is not proof of a validated restore)'
		} else {
			'no /etc/snapper/configs/root; no root snapshot configuration is recorded'
		}
	}
	timers_ok := probe.timeline_timer_unit && probe.cleanup_timer_unit
	checks << DoctorCheck{
		name:   'retention-timers'
		ok:     timers_ok
		detail: if timers_ok {
			'snapper timeline/cleanup timer units present (unit presence does not assert enablement or GC success)'
		} else {
			'snapper timer units missing (timeline: ${probe.timeline_timer_unit}, cleanup: ${probe.cleanup_timer_unit}); bounded retention would not run'
		}
	}
	return checks
}

pub fn recovery_doctor_result_from(probe RecoveryProbe) CommandResult {
	checks := recovery_doctor_checks(probe)
	mut lines := []string{}
	mut failed := 0
	mut data := map[string]string{}
	for c in checks {
		mark := if c.ok { 'ok' } else { 'FAIL' }
		if !c.ok {
			failed++
		}
		lines << '${mark}  ${c.name}: ${redact_secrets(c.detail)}'
		data[c.name] = if c.ok { 'ok' } else { 'fail' }
	}
	data['snapshot_backend'] = probe.backend
	data['root_fstype'] = probe.root_fstype
	data['snapshots_store'] = if probe.snapshots_mounted { 'mounted' } else { 'absent' }
	if failed == 0 {
		lines << 'recovery doctor: all ${checks.len} checks passed'
	} else {
		lines << 'recovery doctor: ${failed}/${checks.len} checks failed'
	}
	if probe.backend == 'none' || probe.backend.len == 0 {
		lines << snapshot_unavailable_line
	} else {
		lines << 'Readiness is not proof of recovery: a restore counts as supported only after the VM acceptance in docs/SNAPSHOT_BACKEND_CONTRACT.md passes.'
	}
	return CommandResult{
		command: 'recovery doctor'
		ok:      failed == 0
		message: lines.join('\n')
		data:    data
	}
}

pub fn recovery_doctor_result() CommandResult {
	return recovery_doctor_result_from(recovery_probe())
}
