module hornero_cli

import hornero_core

pub const playground_verbs = ['doctor', 'profiles', 'scenarios', 'status', 'up', 'down']
pub const presenter_verbs = ['status', 'start', 'stop', 'record', 'stop-recording', 'export']

pub struct PlaygroundCmdOptions {
pub:
	verb                  string
	kind                  string = 'all'
	provider              string = hornero_core.playground_default_provider
	profile               string = hornero_core.playground_default_image_profile
	resolution            string = hornero_core.presenter_default_resolution
	image                 string
	iso                   string
	ram                   string = '4G'
	cpus                  int    = 4
	confirm_paid_provider bool
	dry_run               bool
	yes                   bool
}

pub struct PresenterCmdOptions {
pub:
	verb       string
	resolution string = hornero_core.presenter_default_resolution
	scenario   string
	fps        int = hornero_core.presenter_default_fps
	output     string
	dry_run    bool
	yes        bool
}

fn pg_flag_val(args []string, i int, flag string, example string) !(string, int) {
	a := args[i]
	if a.contains('=') {
		v := a.all_after('=')
		if v.len == 0 {
			return error('${flag} needs a value.\nExample: ${example}')
		}
		return v, i + 1
	}
	if i + 1 >= args.len {
		return error('${flag} needs a value.\nExample: ${example}')
	}
	return args[i + 1], i + 2
}

fn pg_flag_name(a string) string {
	return if a.contains('=') { a.all_before('=') } else { a }
}

pub fn parse_playground_cmd(args []string) !PlaygroundCmdOptions {
	if args.len == 0 {
		return error('missing playground subcommand (${playground_verbs.join(', ')}).\nExample: horneroctl playground doctor --json')
	}
	verb := args[0]
	if verb !in playground_verbs {
		return error('unknown playground subcommand: ${verb} (expected: ${playground_verbs.join(', ')}).\nExample: horneroctl playground profiles --json')
	}

	mut kind := 'all'
	mut provider := hornero_core.playground_default_provider
	mut profile := hornero_core.playground_default_image_profile
	mut resolution := hornero_core.presenter_default_resolution
	mut image := ''
	mut iso := ''
	mut ram := '4G'
	mut cpus := 4
	mut confirm_paid := false
	mut dry_run := false
	mut yes := false

	mut i := 1
	for i < args.len {
		a := args[i]
		name := pg_flag_name(a)
		if verb == 'doctor' || verb == 'scenarios' || verb == 'status' {
			if a.starts_with('-') {
				return error('unknown flag for playground ${verb}: ${a}.\nExample: horneroctl playground ${verb} --json')
			}
			return error('unexpected argument for playground ${verb}: ${a}.\nExample: horneroctl playground ${verb} --json')
		}
		if verb == 'profiles' {
			if name == '--kind' {
				v, next := pg_flag_val(args, i, '--kind', 'horneroctl playground profiles --kind display --json')!
				kind = v
				i = next
				continue
			}
			if a.starts_with('-') {
				return error('unknown flag for playground profiles: ${a}.\nExample: horneroctl playground profiles --json')
			}
			return error('unexpected argument for playground profiles: ${a}.\nExample: horneroctl playground profiles --json')
		}
		if verb == 'down' {
			match name {
				'--dry-run' {
					dry_run = true
					i++
					continue
				}
				'--yes' {
					yes = true
					i++
					continue
				}
				else {
					if a.starts_with('-') {
						return error('unknown flag for playground down: ${a}.\nExample: horneroctl playground down --dry-run')
					}
					return error('unexpected argument for playground down: ${a}.\nExample: horneroctl playground down --dry-run')
				}
			}
		}
		// verb == 'up'
		match name {
			'--dry-run' {
				dry_run = true
				i++
			}
			'--yes' {
				yes = true
				i++
			}
			'--confirm-paid-provider' {
				confirm_paid = true
				i++
			}
			'--provider' {
				v, next := pg_flag_val(args, i, '--provider', 'horneroctl playground up --provider local --dry-run')!
				provider = v
				i = next
			}
			'--profile' {
				v, next := pg_flag_val(args, i, '--profile', 'horneroctl playground up --profile standard-vm --dry-run')!
				profile = v
				i = next
			}
			'--resolution' {
				v, next := pg_flag_val(args, i, '--resolution', 'horneroctl playground up --resolution 1920x1080 --dry-run')!
				resolution = v
				i = next
			}
			'--image' {
				v, next := pg_flag_val(args, i, '--image', 'horneroctl playground up --image ./horneroos.qcow2 --dry-run')!
				image = v
				i = next
			}
			'--iso' {
				v, next := pg_flag_val(args, i, '--iso', 'horneroctl playground up --iso ./horneroos.iso --dry-run')!
				iso = v
				i = next
			}
			'--ram' {
				v, next := pg_flag_val(args, i, '--ram', 'horneroctl playground up --ram 4G --dry-run')!
				ram = v
				i = next
			}
			'--cpus' {
				v, next := pg_flag_val(args, i, '--cpus', 'horneroctl playground up --cpus 4 --dry-run')!
				if !v.bytes().all(it >= `0` && it <= `9`) || v.len == 0 {
					return error('--cpus must be a positive integer.\nExample: horneroctl playground up --cpus 4 --dry-run')
				}
				cpus = v.int()
				i = next
			}
			else {
				if a.starts_with('-') {
					return error('unknown flag for playground up: ${a}.\nExample: horneroctl playground up --provider local --dry-run')
				}
				return error('unexpected argument for playground up: ${a}.\nExample: horneroctl playground up --provider local --dry-run')
			}
		}
	}

	return PlaygroundCmdOptions{
		verb:                  verb
		kind:                  kind
		provider:              provider
		profile:               profile
		resolution:            resolution
		image:                 image
		iso:                   iso
		ram:                   ram
		cpus:                  cpus
		confirm_paid_provider: confirm_paid
		dry_run:               dry_run
		yes:                   yes
	}
}

pub fn parse_presenter_cmd(args []string) !PresenterCmdOptions {
	if args.len == 0 {
		return error('missing presenter subcommand (${presenter_verbs.join(', ')}).\nExample: horneroctl presenter status --json')
	}
	verb := args[0]
	if verb !in presenter_verbs {
		return error('unknown presenter subcommand: ${verb} (expected: ${presenter_verbs.join(', ')}).\nExample: horneroctl presenter start --resolution 1920x1080 --dry-run')
	}

	mut resolution := hornero_core.presenter_default_resolution
	mut scenario := ''
	mut fps := hornero_core.presenter_default_fps
	mut output := ''
	mut dry_run := false
	mut yes := false

	mut i := 1
	for i < args.len {
		a := args[i]
		name := pg_flag_name(a)
		if verb == 'status' {
			if a.starts_with('-') {
				return error('unknown flag for presenter status: ${a}.\nExample: horneroctl presenter status --json')
			}
			return error('unexpected argument for presenter status: ${a}.\nExample: horneroctl presenter status --json')
		}
		match name {
			'--dry-run' {
				dry_run = true
				i++
			}
			'--yes' {
				yes = true
				i++
			}
			'--resolution' {
				if verb == 'stop' {
					return error('--resolution is not supported for presenter stop.\nExample: horneroctl presenter stop --dry-run')
				}
				v, next := pg_flag_val(args, i, '--resolution', 'horneroctl presenter ${verb} --resolution 1920x1080 --dry-run')!
				resolution = v
				i = next
			}
			'--scenario' {
				if verb == 'stop' {
					return error('--scenario is not supported for presenter stop.\nExample: horneroctl presenter stop --dry-run')
				}
				v, next := pg_flag_val(args, i, '--scenario', 'horneroctl presenter ${verb} --scenario first-flight --dry-run')!
				scenario = v
				i = next
			}
			'--fps' {
				if verb == 'stop' {
					return error('--fps is not supported for presenter stop.\nExample: horneroctl presenter stop --dry-run')
				}
				v, next := pg_flag_val(args, i, '--fps', 'horneroctl presenter ${verb} --fps 60 --dry-run')!
				if v.len == 0 || !v.bytes().all(it >= `0` && it <= `9`) {
					return error('--fps must be 30 or 60.\nExample: horneroctl presenter ${verb} --fps 60 --dry-run')
				}
				fps = v.int()
				i = next
			}
			'--output' {
				if verb !in ['record', 'export'] {
					return error('--output belongs to presenter record|export.\nExample: horneroctl presenter export --scenario first-flight --output ./out --dry-run')
				}
				v, next := pg_flag_val(args, i, '--output', 'horneroctl presenter ${verb} --output ./out --dry-run')!
				output = v
				i = next
			}
			else {
				if a.starts_with('-') {
					return error('unknown flag for presenter ${verb}: ${a}.\nExample: horneroctl presenter ${verb} --dry-run')
				}
				return error('unexpected argument for presenter ${verb}: ${a}.\nExample: horneroctl presenter ${verb} --dry-run')
			}
		}
	}

	return PresenterCmdOptions{
		verb:       verb
		resolution: resolution
		scenario:   scenario
		fps:        fps
		output:     output
		dry_run:    dry_run
		yes:        yes
	}
}

fn run_playground(args []string, mode hornero_core.RenderMode) int {
	opts := parse_playground_cmd(args) or {
		return render_error(hornero_core.err_usage('playground.usage', err.msg()), mode)
	}
	return match opts.verb {
		'doctor' {
			render(hornero_core.playground_doctor(), mode)
		}
		'profiles' {
			render(hornero_core.playground_profiles_result(opts.kind), mode)
		}
		'scenarios' {
			render(hornero_core.playground_scenarios_result(), mode)
		}
		'status' {
			render(hornero_core.playground_status_result(), mode)
		}
		'up' {
			render(hornero_core.playground_up_result(hornero_core.PlaygroundUpOptions{
				provider:              opts.provider
				profile:               opts.profile
				resolution:            opts.resolution
				image:                 opts.image
				iso:                   opts.iso
				ram:                   opts.ram
				cpus:                  opts.cpus
				confirm_paid_provider: opts.confirm_paid_provider
				dry_run:               opts.dry_run
				yes:                   opts.yes
			}), mode)
		}
		'down' {
			render(hornero_core.playground_down_result(opts.dry_run, opts.yes), mode)
		}
		else {
			render_error(hornero_core.err_usage('playground.usage',
				'unknown playground subcommand.\nExample: horneroctl playground doctor --json'),
				mode)
		}
	}
}

fn run_presenter(args []string, mode hornero_core.RenderMode) int {
	opts := parse_presenter_cmd(args) or {
		return render_error(hornero_core.err_usage('presenter.usage', err.msg()), mode)
	}
	return render(hornero_core.presenter_execute_result(hornero_core.PresenterOptions{
		action:     opts.verb
		resolution: opts.resolution
		scenario:   opts.scenario
		fps:        opts.fps
		output:     opts.output
		dry_run:    opts.dry_run
		yes:        opts.yes
	}), mode)
}
