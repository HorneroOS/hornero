module hornero_cli

import hornero_core

// Option parser: `appearance chromatic <verb> ...` (RFC 0002 §10).
// Unknown flags always carry a correct Example (exit-2 contract).

const chromatic_verbs = ['status', 'analyze', 'preview', 'apply', 'follow', 'rollback', 'history',
	'save', 'export', 'import', 'variants', 'off', 'doctor', 'templates', 'list', 'rename', 'delete']

pub fn parse_chromatic(args []string) !hornero_core.ChromaticOptions {
	if args.len == 0 {
		return error('missing verb (${chromatic_verbs.join('|')}).\nExample: horneroctl appearance chromatic status')
	}
	verb := args[0]
	if verb !in chromatic_verbs {
		return error('unknown chromatic verb: ${verb}.\nRun: horneroctl appearance chromatic --help')
	}
	mut rest := args[1..].clone()
	mut sub := ''
	if verb == 'templates' {
		if rest.len == 0 || rest[0] !in ['list', 'render', 'check'] {
			return error('templates needs list|render|check.\nExample: horneroctl appearance chromatic templates list')
		}
		sub = rest[0]
		rest = rest[1..].clone()
	}
	mut seeds := []string{}
	mut source := ''
	mut variant := ''
	mut mode := ''
	mut contrast := ''
	mut depth := ''
	mut chroma := ''
	mut hue_shift := ''
	mut dry_run := false
	mut yes := false
	mut no_persist := false
	mut force := false
	mut all := false
	mut steps := 1
	mut id := ''
	mut name := ''
	mut from := ''
	mut output := ''
	mut positional := []string{}
	mut i := 0
	value_flags := ['--source', '--seed', '--variant', '--mode', '--contrast', '--depth', '--chroma',
		'--hue-shift', '--steps', '--id', '--name', '--from', '--output']
	for i < rest.len {
		a := rest[i]
		if a in ['--dry-run', '--yes', '--no-persist', '--force', '--all'] {
			match a {
				'--dry-run' { dry_run = true }
				'--yes' { yes = true }
				'--no-persist' { no_persist = true }
				'--force' { force = true }
				else { all = true }
			}
			i++
			continue
		}
		if a in value_flags {
			if i + 1 >= rest.len {
				return error('${a} needs a value.\nExample: horneroctl appearance chromatic ${verb} ${a} <value>')
			}
			v := rest[i + 1]
			match a {
				'--source' { source = v }
				'--seed' { seeds << v }
				'--variant' { variant = v }
				'--mode' { mode = v }
				'--contrast' { contrast = v }
				'--depth' { depth = v }
				'--chroma' { chroma = v }
				'--hue-shift' { hue_shift = v }
				'--steps' {
					if !v.bytes().all(it >= `0` && it <= `9`) || v.int() < 1 {
						return error('--steps wants a positive integer.\nExample: horneroctl appearance chromatic rollback --steps 2 --yes')
					}
					steps = v.int()
				}
				'--id' { id = v }
				'--name' { name = v }
				'--from' { from = v }
				else { output = v }
			}
			i += 2
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl appearance chromatic ${verb} --dry-run')
		}
		positional << a
		i++
	}
	mut file := ''
	if verb in ['import', 'rename', 'delete'] || (verb == 'templates' && sub == 'check') {
		if positional.len > 1 {
			return error('unexpected argument: ${positional[1]}.\nRun: horneroctl appearance chromatic --help')
		}
		if positional.len == 1 {
			if verb in ['rename', 'delete'] {
				id = positional[0]
			} else {
				file = positional[0]
			}
		}
	} else if positional.len > 0 {
		return error('unexpected argument: ${positional[0]}.\nExample: horneroctl appearance chromatic ${verb} --dry-run')
	}
	return hornero_core.ChromaticOptions{
		verb:       verb
		sub:        sub
		source:     source
		seeds:      seeds
		variant:    variant
		mode:       mode
		contrast:   contrast
		depth:      depth
		chroma:     chroma
		hue_shift:  hue_shift
		dry_run:    dry_run
		yes:        yes
		no_persist: no_persist
		force:      force
		all:        all
		steps:      steps
		id:         id
		name:       name
		from:       from
		output:     output
		file:       file
	}
}

// hornero_core_preview is a thin seam so adapter tests can inspect the
// reply envelope that --json prints.
fn hornero_core_preview(o hornero_core.ChromaticOptions) hornero_core.ChromaticReply {
	return hornero_core.chromatic_preview(o)
}
