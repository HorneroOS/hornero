module hornero_core

import os

fn test_grub_boot_menu_doctor_skips_when_no_grub_cfg() {
	tmp := os.join_path(os.temp_dir(), 'hornero_grub_none_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	checks := grub_boot_menu_doctor_checks(os.join_path(tmp, 'modules'), os.join_path(tmp, 'boot'),
		os.join_path(tmp, 'boot', 'grub', 'grub.cfg'))
	assert checks.len == 0
}

fn test_grub_boot_menu_doctor_warns_when_installed_kernel_missing() {
	tmp := os.join_path(os.temp_dir(), 'hornero_grub_stale_${os.getpid()}')
	mods := os.join_path(tmp, 'modules')
	boot := os.join_path(tmp, 'boot')
	grub_dir := os.join_path(boot, 'grub')
	os.mkdir_all(os.join_path(mods, '6.12.1-arch1-1')) or { panic(err) }
	os.mkdir_all(os.join_path(mods, '6.6.60-1-lts')) or { panic(err) }
	os.mkdir_all(grub_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	os.write_file(os.join_path(mods, '6.12.1-arch1-1', 'pkgbase'), 'linux\n') or { panic(err) }
	os.write_file(os.join_path(mods, '6.6.60-1-lts', 'pkgbase'), 'linux-lts\n') or { panic(err) }
	os.write_file(os.join_path(boot, 'vmlinuz-linux'), 'elf') or { panic(err) }
	os.write_file(os.join_path(boot, 'vmlinuz-linux-lts'), 'elf') or { panic(err) }
	grub_cfg := os.join_path(grub_dir, 'grub.cfg')
	os.write_file(grub_cfg, "menuentry 'HorneroOS' {\n\tlinux /boot/vmlinuz-linux root=UUID=123 rw\n}\n") or {
		panic(err)
	}

	checks := grub_boot_menu_doctor_checks(mods, boot, grub_cfg)
	assert checks.len == 1
	assert checks[0].name == 'grub-boot-menu'
	assert checks[0].ok == true
	assert checks[0].warn == true
	assert checks[0].detail.contains('vmlinuz-linux-lts')
	assert checks[0].detail.contains('grub-mkconfig')
}

fn test_grub_boot_menu_doctor_passes_when_all_kernels_listed() {
	tmp := os.join_path(os.temp_dir(), 'hornero_grub_ok_${os.getpid()}')
	mods := os.join_path(tmp, 'modules')
	boot := os.join_path(tmp, 'boot')
	grub_dir := os.join_path(boot, 'grub')
	os.mkdir_all(os.join_path(mods, '6.12.1-arch1-1')) or { panic(err) }
	os.mkdir_all(os.join_path(mods, '6.6.60-1-lts')) or { panic(err) }
	os.mkdir_all(grub_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	os.write_file(os.join_path(mods, '6.12.1-arch1-1', 'pkgbase'), 'linux\n') or { panic(err) }
	os.write_file(os.join_path(mods, '6.6.60-1-lts', 'pkgbase'), 'linux-lts\n') or { panic(err) }
	os.write_file(os.join_path(boot, 'vmlinuz-linux'), 'elf') or { panic(err) }
	os.write_file(os.join_path(boot, 'vmlinuz-linux-lts'), 'elf') or { panic(err) }
	grub_cfg := os.join_path(grub_dir, 'grub.cfg')
	os.write_file(grub_cfg, "menuentry 'HorneroOS' {\n\tlinux /vmlinuz-linux root=UUID=123 rw\n}\nmenuentry 'HorneroOS LTS' {\n\tlinuxefi /boot/vmlinuz-linux-lts root=UUID=123 rw\n}\n") or {
		panic(err)
	}

	checks := grub_boot_menu_doctor_checks(mods, boot, grub_cfg)
	assert checks.len == 1
	assert checks[0].name == 'grub-boot-menu'
	assert checks[0].ok == true
	assert checks[0].warn == false
	assert checks[0].detail.contains('vmlinuz-linux')
	assert checks[0].detail.contains('vmlinuz-linux-lts')
}
