module hornero_core

fn test_profile_yaml_section_value() {
	cfg := 'model:\n  provider: custom\napprovals:\n  mode: smart\nsecurity:\n  protected_instruction_files: false\n'
	assert assistant_yaml_section_value(cfg, 'approvals', 'mode') == 'smart'
	assert assistant_yaml_section_value(cfg, 'security', 'protected_instruction_files') == 'false'
	assert assistant_yaml_section_value(cfg, 'model', 'mode') == ''
	assert assistant_yaml_section_value(cfg, 'missing', 'mode') == ''
}

fn test_profile_findings_flag_smart_mode() {
	cfg := 'approvals:\n  mode: smart\n'
	findings := assistant_profile_findings(cfg)
	assert findings[0].ok == false
	fixed := assistant_profile_fixed_config(cfg)
	assert assistant_yaml_section_value(fixed, 'approvals', 'mode') == 'manual'
	assert assistant_yaml_section_value(fixed, 'security', 'protected_instruction_files') == 'true'
	// Idempotent: fixing twice changes nothing further.
	assert assistant_profile_fixed_config(fixed) == fixed
	// Other config survives untouched.
	cfg2 := 'model:\n  provider: custom\n  default: gpt-5\napprovals:\n  mode: manual\n'
	fixed2 := assistant_profile_fixed_config(cfg2)
	assert fixed2.contains('default: gpt-5')
	assert assistant_profile_findings(fixed2)[0].ok
}

fn test_profile_findings_missing_config_fails_closed() {
	findings := assistant_profile_findings('')
	assert findings[0].ok == false
}
