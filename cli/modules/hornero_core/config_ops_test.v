import os

fn test_resolve_materialize_bin_packaged_seed_contract() {
	src := os.read_file(@FILE.all_before_last('/') + '/config_ops.v') or { panic(err) }
	// The packaged missing-only seed is the last-resort backend so a
	// package-only (install-on-Arch) system can seed an existing
	// account without a config checkout on PATH.
	assert src.contains("'/usr/share/hornero/seed-user.sh'")
	assert src.contains("find_on_path('materialize.sh')")
	// PATH/checkout backends keep priority over the packaged seed.
	path_idx := src.index("find_on_path('materialize.sh')") or { panic('PATH lookup missing') }
	seed_idx := src.index("'/usr/share/hornero/seed-user.sh'") or { panic('packaged seed missing') }
	assert path_idx < seed_idx
}
