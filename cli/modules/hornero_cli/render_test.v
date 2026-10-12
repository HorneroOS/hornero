module hornero_cli

import hornero_core
import x.json2

fn test_error_json_uses_a_boolean_ok_field() {
	encoded := error_json(hornero_core.err_usage('flag.unknown', 'bad "flag"'))
	fields := json2.decode[map[string]json2.Any](encoded) or {
		assert false, err.msg()
		return
	}
	assert fields['ok'] is bool
	assert !fields['ok'].bool()
	assert fields['code'].str() == 'flag.unknown'
	assert fields['message'].str() == 'bad "flag"'
}
