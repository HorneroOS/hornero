module hornero_cli

pub const profile_verbs = ['list', 'show', 'capture', 'diff', 'apply', 'revert', 'delete', 'launch-apps',
	'export', 'import']

pub struct ProfileCmdOptions {
pub:
	verb                string
	id                  string
	file                string
	name                string
	description         string
	domains             []string
	apps                []string
	app_filter          string
	no_apps             bool
	activate            bool
	no_restart_pipewire bool
	launch_apps         bool
	to                  string = 'previous'
	portable            bool
	dry_run             bool
	yes                 bool
}

fn profile_require_value(args []string, i int, flag string, example string) !string {
	if i + 1 >= args.len {
		return error('${flag} needs a value.\nExample: ${example}')
	}
	return args[i + 1]
}

pub fn parse_profile_cmd(args []string) !ProfileCmdOptions {
	if args.len == 0 {
		return error('missing subcommand (${profile_verbs.join(', ')}).\nExample: horneroctl profile list --json')
	}
	verb := args[0]
	if verb !in profile_verbs {
		return error('unknown profile subcommand: ${verb} (expected: ${profile_verbs.join(', ')}).\nExample: horneroctl profile list')
	}
	mut id := ''
	mut file := ''
	mut name := ''
	mut description := ''
	mut domains := []string{}
	mut apps := []string{}
	mut app_filter := ''
	mut no_apps := false
	mut activate := false
	mut no_restart_pw := false
	mut launch_apps := false
	mut to := 'previous'
	mut portable := false
	mut dry_run := false
	mut yes := false
	mut positionals := []string{}

	mut i := 1
	for i < args.len {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a == '--yes' {
			yes = true
			i++
			continue
		}
		match verb {
			'capture' {
				match a {
					'--name' {
						name = profile_require_value(args, i, '--name', 'horneroctl profile capture music --name "Music Studio" --yes')!
						i += 2
						continue
					}
					'--description' {
						description = profile_require_value(args, i, '--description', 'horneroctl profile capture music --description "DAW setup" --yes')!
						i += 2
						continue
					}
					'--domains' {
						domains << profile_require_value(args, i, '--domains', 'horneroctl profile capture music --domains experience,audio --yes')!
						i += 2
						continue
					}
					'--app' {
						apps << profile_require_value(args, i, '--app', 'horneroctl profile capture music --app reaper --yes')!
						i += 2
						continue
					}
					'--no-apps' {
						no_apps = true
						i++
						continue
					}
					'--activate' {
						activate = true
						i++
						continue
					}
					else {}
				}
			}
			'apply' {
				match a {
					'--domains' {
						domains << profile_require_value(args, i, '--domains', 'horneroctl profile apply music --domains audio,power --yes')!
						i += 2
						continue
					}
					'--no-restart-pipewire' {
						no_restart_pw = true
						i++
						continue
					}
					'--launch-apps' {
						launch_apps = true
						i++
						continue
					}
					else {}
				}
			}
			'revert' {
				match a {
					'--to' {
						to = profile_require_value(args, i, '--to', 'horneroctl profile revert --to baseline --yes')!
						i += 2
						continue
					}
					'--no-restart-pipewire' {
						no_restart_pw = true
						i++
						continue
					}
					else {}
				}
			}
			'launch-apps' {
				if a == '--app' {
					app_filter = profile_require_value(args, i, '--app', 'horneroctl profile launch-apps music --app reaper --yes')!
					i += 2
					continue
				}
			}
			'export' {
				if a == '--portable' {
					portable = true
					i++
					continue
				}
			}
			'import' {
				if a == '--id' {
					id = profile_require_value(args, i, '--id', 'horneroctl profile import ./music.json --id studio-main --yes')!
					i += 2
					continue
				}
			}
			else {}
		}
		if a.starts_with('-') {
			return error('unknown flag for profile ${verb}: ${a}.\nExample: horneroctl profile ${verb} --help')
		}
		positionals << a
		i++
	}

	match verb {
		'list' {
			if dry_run || yes {
				return error('unexpected flag for profile list.\nExample: horneroctl profile list --json')
			}
			if positionals.len > 0 {
				return error('unexpected argument: ${positionals[0]}.\nExample: horneroctl profile list')
			}
		}
		'show', 'diff' {
			if dry_run || yes {
				return error('unexpected flag for profile ${verb}.\nExample: horneroctl profile ${verb} music-prod')
			}
			if positionals.len != 1 {
				return error('expected exactly one profile id.\nExample: horneroctl profile ${verb} music-prod')
			}
			id = positionals[0]
		}
		'capture', 'apply', 'delete', 'launch-apps' {
			if positionals.len != 1 {
				return error('expected exactly one profile id.\nExample: horneroctl profile ${verb} music-prod --dry-run')
			}
			id = positionals[0]
		}
		'revert' {
			if positionals.len > 0 {
				return error('unexpected argument: ${positionals[0]}.\nExample: horneroctl profile revert --to previous --dry-run')
			}
		}
		'export' {
			if positionals.len != 2 {
				return error('expected <id> <file>.\nExample: horneroctl profile export music-prod ./music-prod.json --dry-run')
			}
			id = positionals[0]
			file = positionals[1]
		}
		'import' {
			if positionals.len != 1 {
				return error('expected <file>.\nExample: horneroctl profile import ./music-prod.json --dry-run')
			}
			file = positionals[0]
		}
		else {}
	}

	return ProfileCmdOptions{
		verb:                verb
		id:                  id
		file:                file
		name:                name
		description:         description
		domains:             domains
		apps:                apps
		app_filter:          app_filter
		no_apps:             no_apps
		activate:            activate
		no_restart_pipewire: no_restart_pw
		launch_apps:         launch_apps
		to:                  to
		portable:            portable
		dry_run:             dry_run
		yes:                 yes
	}
}
