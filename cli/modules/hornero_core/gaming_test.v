module hornero_core

import os

// Gaming selection/doctor contract tests. Everything lives under /tmp
// with HORNERO_GAMING_SELECTION_FILE overrides; each test unsets what it
// sets.

const gaming_test_root = '/tmp/hx-gaming-test'

fn gaming_set_file(tag string) string {
	dir := '${gaming_test_root}/${tag}'
	if os.exists(dir) {
		os.rmdir_all(dir) or {}
	}
	os.mkdir_all(dir) or { assert false }
	path := '${dir}/gaming-selection.json'
	os.setenv('HORNERO_GAMING_SELECTION_FILE', path, true)
	return path
}

fn gaming_unset_file() {
	os.unsetenv('HORNERO_GAMING_SELECTION_FILE')
}

fn test_gaming_selection_roundtrip() {
	path := gaming_set_file('roundtrip')
	defer {
		gaming_unset_file()
	}
	sel := GamingSelection{
		schema_version:  gaming_schema_version
		specializations: ['desktop-gaming']
		applications:    ['steam']
	}
	os.write_file(path, gaming_encode_selection(sel)) or { assert false }
	loaded, present := load_gaming_selection() or {
		assert false, err.msg()
		return
	}
	assert present
	assert loaded.specializations == ['desktop-gaming']
	assert loaded.applications == ['steam']
}

fn test_gaming_selection_fails_closed_on_unknown_ids() {
	path := gaming_set_file('unknown')
	defer {
		gaming_unset_file()
	}
	os.write_file(path, '{"schemaVersion": 1, "specializations": ["esports"], "applications": []}\n') or {
		assert false
	}
	load_gaming_selection() or {
		assert err.msg().contains('unknown gaming specialization')
		return
	}
	assert false, 'unknown specialization must fail closed'
}

fn test_gaming_selection_missing_file_is_empty_state() {
	gaming_set_file('missing')
	defer {
		gaming_unset_file()
	}
	_, present := load_gaming_selection() or {
		assert false, err.msg()
		return
	}
	assert !present
}

fn test_gaming_doctor_reports_selection_and_capability_checks() {
	gaming_set_file('doctor')
	defer {
		gaming_unset_file()
	}
	checks := gaming_doctor_checks()
	names := checks.map(it.name)
	assert 'gaming-selection' in names
	assert 'vulkan-icd' in names
	assert 'controllers' in names
	assert 'recovery-readiness' in names
	assert 'gpu-driver-coherence' in names
	controllers := checks.filter(it.name == 'controllers')[0]
	assert controllers.ok
	assert controllers.detail.contains('not Handheld qualification') || controllers.detail.contains('Handheld')
	selection := checks.filter(it.name == 'gaming-selection')[0]
	assert selection.ok
	assert selection.detail.contains('Preview')
	assert 'gpu-topology' in names
	topology := checks.filter(it.name == 'gpu-topology')[0]
	assert topology.ok
	assert topology.detail.contains('detection is not qualification')
}

fn test_gaming_doctor_continues_after_invalid_selection() {
	path := gaming_set_file('invalid-doctor')
	defer {
		gaming_unset_file()
	}
	os.write_file(path, '{"schemaVersion": 1, "specializations": ["esports"], "applications": []}\n') or {
		assert false
	}
	checks := gaming_doctor_checks()
	names := checks.map(it.name)
	selection := checks.filter(it.name == 'gaming-selection')[0]
	assert !selection.ok
	assert 'vulkan-icd' in names
	assert 'recovery-readiness' in names
	// With Steam unselected, a missing binary is informational and a
	// present one is fine: either way the check must not fail.
	steam := checks.filter(it.name == 'steam')[0]
	assert steam.ok
}

fn test_gpu_coherence_no_nvidia_is_neutral_ok() {
	c := gpu_coherence_check(GpuCoherence{
		has_nvidia:        false
		running_kernel:    '6.1.0'
		installed_kernels: ['6.1.0']
	})
	assert c.ok
	assert c.detail.contains('hardware-neutral')
}

fn test_gpu_coherence_userspace_without_module_is_actionable() {
	// pelicano P0-08: nvidia-utils installed, no kernel module package.
	c := gpu_coherence_check(GpuCoherence{
		has_nvidia:        true
		has_userspace:     true
		running_kernel:    '6.1.0'
		installed_kernels: ['6.1.0']
	})
	assert !c.ok
	assert c.detail.contains('nvidia-open')
	assert c.detail.contains('.run')
}

fn test_gpu_coherence_kernel_not_rebooted_wins_over_driver() {
	// P1-13: do not diagnose a broken driver before reboot.
	c := gpu_coherence_check(GpuCoherence{
		has_nvidia:        true
		has_userspace:     true
		running_kernel:    '6.1.0'
		installed_kernels: ['6.2.0']
	})
	assert !c.ok
	assert c.detail.contains('not rebooted')
}

fn test_gpu_coherence_loaded_module_ok_without_claiming_nvenc() {
	c := gpu_coherence_check(GpuCoherence{
		has_nvidia:        true
		module_version:    '570.0'
		has_userspace:     true
		running_kernel:    '6.1.0'
		installed_kernels: ['6.1.0']
	})
	assert c.ok
	assert c.detail.contains('not NVENC')
}

fn test_gpu_topology_single_dgpu() {
	c := gpu_topology_check(GpuTopology{
		devices: [GpuPciDevice{
			vendor_id: '0x10de'
			class_id:  '0x030200'
			boot_vga:  true
		}]
	})
	assert c.ok
	assert gpu_topology_class(GpuTopology{
		devices: [GpuPciDevice{
			vendor_id: '1002'
			class_id:  '0x030000'
		}]
	}) == 'single-dGPU'
	assert c.detail.contains('single-dGPU')
	assert c.detail.contains('nvidia=1')
	assert c.detail.contains('boot_vga=1')
	assert c.detail.contains('detection is not qualification')
}

fn test_gpu_topology_hybrid() {
	p := GpuTopology{
		devices: [
			GpuPciDevice{
				vendor_id: '0x8086'
				class_id:  '0x030000'
				boot_vga:  true
			},
			GpuPciDevice{
				vendor_id: '0x10de'
				class_id:  '0x030200'
			},
		]
	}
	c := gpu_topology_check(p)
	assert c.ok
	assert gpu_topology_class(p) == 'hybrid'
	assert c.detail.contains('hybrid')
	assert c.detail.contains('2 display-class')
	assert c.detail.contains('intel=1')
	assert c.detail.contains('nvidia=1')
	assert c.detail.contains('detection is not qualification')
}

fn test_gpu_topology_integrated_only() {
	p := GpuTopology{
		devices: [GpuPciDevice{
			vendor_id: '8086'
			class_id:  '0x030000'
			boot_vga:  true
		}]
	}
	c := gpu_topology_check(p)
	assert c.ok
	assert gpu_topology_class(p) == 'integrated-only'
	assert c.detail.contains('integrated-only')
	assert c.detail.contains('detection is not qualification')
}

fn test_gpu_topology_virtual() {
	p := GpuTopology{
		devices: [GpuPciDevice{
			vendor_id: '0x1234'
			class_id:  '0x030000'
			boot_vga:  true
		}]
	}
	c := gpu_topology_check(p)
	assert c.ok
	assert gpu_topology_class(p) == 'virtual'
	assert c.detail.contains('virtual=1')
	assert c.detail.contains('detection is not qualification')
}

fn test_gpu_topology_unknown_and_non_display_ignored() {
	empty := gpu_topology_check(GpuTopology{})
	assert empty.ok
	assert gpu_topology_class(GpuTopology{}) == 'unknown'
	assert empty.detail.contains('unknown')
	assert empty.detail.contains('detection is not qualification')
	other := GpuTopology{
		devices: [GpuPciDevice{
			vendor_id: '0x9999'
			class_id:  '0x030000'
		}]
	}
	assert gpu_topology_class(other) == 'unknown'
	assert gpu_topology_check(other).detail.contains('other=1')
	// A non-display NVIDIA function (e.g. audio, class 0x04) must not
	// turn an integrated-only machine into a hybrid.
	mixed := GpuTopology{
		devices: [
			GpuPciDevice{
				vendor_id: '0x8086'
				class_id:  '0x030000'
				boot_vga:  true
			},
			GpuPciDevice{
				vendor_id: '0x10de'
				class_id:  '0x040300'
			},
		]
	}
	assert gpu_topology_class(mixed) == 'integrated-only'
	assert gpu_topology_check(mixed).detail.contains('1 display-class')
}

fn test_gaming_selection_set_roundtrip_and_dry_run() {
	path := gaming_set_file('set')
	defer {
		gaming_unset_file()
	}
	dry := gaming_selection_set_result(['handheld'], ['lutris'], true)
	assert dry.ok
	_, present_before := load_gaming_selection() or {
		assert false, err.msg()
		return
	}
	assert !present_before
	done := gaming_selection_set_result(['handheld'], ['lutris'], false)
	assert done.ok
	loaded, present := load_gaming_selection() or {
		assert false, err.msg()
		return
	}
	assert present
	assert loaded.specializations == ['handheld']
	assert loaded.applications == ['lutris']
	assert path == gaming_selection_file()
	bad := gaming_selection_set_result(['esports'], [], false)
	assert !bad.ok
}

fn test_gaming_ids_cover_catalogue_model() {
	assert gaming_specialization_ids.len == 6
	assert 'desktop-gaming' in gaming_specialization_ids
	assert 'vr' in gaming_specialization_ids
	assert 'steam' in gaming_application_ids
	assert 'steam' in gaming_opt_in_application_ids
}
