module hornero_core

fn test_parse_mounts_btrfs_with_snapshots_store() {
	content := '/dev/mapper/cryptroot / btrfs rw,subvol=/@ 0 0
/dev/mapper/cryptroot /home btrfs rw,subvol=/@home 0 0
/dev/mapper/cryptroot /.snapshots btrfs rw,subvol=/@snapshots 0 0
proc /proc proc rw 0 0
'
	fstype, store := parse_mounts(content)
	assert fstype == 'btrfs'
	assert store
}

fn test_parse_mounts_ext4_without_store() {
	content := '/dev/sda2 / ext4 rw 0 1
proc /proc proc rw 0 0
'
	fstype, store := parse_mounts(content)
	assert fstype == 'ext4'
	assert !store
}

fn ready_probe() RecoveryProbe {
	return RecoveryProbe{
		backend:             'btrfs-snapper'
		root_fstype:         'btrfs'
		snapshots_mounted:   true
		snapper_bin:         '/usr/bin/snapper'
		snapper_config:      true
		timeline_timer_unit: true
		cleanup_timer_unit:  true
	}
}

fn check_by_name(checks []DoctorCheck, name string) DoctorCheck {
	for c in checks {
		if c.name == name {
			return c
		}
	}
	return DoctorCheck{
		name:   name
		ok:     false
		detail: 'check missing'
	}
}

fn test_recovery_checks_backend_none_is_honest_failure() {
	mut probe := ready_probe()
	probe.backend = 'none'
	checks := recovery_doctor_checks(probe)
	backend := check_by_name(checks, 'snapshot-backend')
	assert !backend.ok
	assert backend.detail.contains('no OS snapshot backend')
	// Even a perfectly prepared layout must not be reported as proven
	// rollback while the shipped backend is 'none'.
	result := recovery_doctor_result_from(probe)
	assert !result.ok
	assert result.data['snapshot_backend'] == 'none'
	assert result.message.contains('not OS rollback')
}

fn test_recovery_checks_non_btrfs_is_plainly_unsupported() {
	mut probe := ready_probe()
	probe.root_fstype = 'ext4'
	checks := recovery_doctor_checks(probe)
	root := check_by_name(checks, 'root-filesystem')
	assert !root.ok
	assert root.detail.contains('unsupported')
}

fn test_recovery_checks_ready_probe_passes_without_restore_claim() {
	checks := recovery_doctor_checks(ready_probe())
	for c in checks {
		assert c.ok, 'expected ${c.name} ok, got: ${c.detail}'
	}
	result := recovery_doctor_result_from(ready_probe())
	assert result.ok
	assert result.data['snapshot_backend'] == 'btrfs-snapper'
	// Readiness probes never claim a restore was proven.
	assert result.message.contains('not proof')
}
