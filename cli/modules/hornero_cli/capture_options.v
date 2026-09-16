module hornero_cli

// Capture option parser: `capture <screenshot|record|clipboard> ...`.
// Error strings always carry a correct Example (exit-2 contract).
// screenshot and record leaves mutate (files, recorder processes) and
// take --dry-run/--yes; clipboard only opens read views and takes
// --dry-run (no --yes, like `welcome open`).

// CaptureCmdOptions covers the whole capture group. group selects the
// dots-* surface; leaf is the record action (start|stop|pause).
pub struct CaptureCmdOptions {
pub:
	group      string // screenshot | record | clipboard
	leaf       string // record action, else ''
	region     bool
	fullscreen bool
	sound      bool
	sr         bool
	fps        int    // record start fps, default 30
	output     string // screenshot --output
	backend    string // clipboard --backend, default auto
	dry_run    bool
	yes        bool
}

fn capture_opt_example(group string, leaf string) string {
	if group == 'record' && leaf.len > 0 {
		return 'horneroctl capture record ${leaf} --dry-run'
	}
	if group.len > 0 {
		return 'horneroctl capture ${group} --dry-run'
	}
	return 'horneroctl capture screenshot --dry-run'
}

// parse_capture_cmd parses `capture <screenshot|record|clipboard>` args.
pub fn parse_capture_cmd(args []string) !CaptureCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl capture screenshot --dry-run')
	}
	group := args[0]
	if group !in ['screenshot', 'record', 'clipboard'] {
		return error('unknown capture subcommand: ${group}.\nRun: horneroctl capture --help')
	}
	mut leaf := ''
	mut rest := args[1..].clone()
	if group == 'record' {
		if rest.len == 0 {
			return error('missing record action.\nExample: horneroctl capture record start --dry-run')
		}
		if rest[0] !in ['start', 'stop', 'pause'] {
			return error('unknown record action: ${rest[0]}.\nRun: horneroctl capture --help')
		}
		leaf = rest[0]
		rest = rest[1..].clone()
	}
	mut region := false
	mut fullscreen := false
	mut sound := false
	mut sr := false
	mut fps := 30
	mut fps_seen := false
	mut output := ''
	mut backend := 'auto'
	mut dry_run := false
	mut yes := false
	ex := capture_opt_example(group, leaf)
	mut i := 0
	for i < rest.len {
		a := rest[i]
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
		if a == '--fullscreen' {
			if group != 'screenshot' {
				return error('unknown flag: ${a}.\nExample: ${ex}')
			}
			fullscreen = true
			i++
			continue
		}
		if a == '--region' {
			if group == 'screenshot' {
				region = true
				i++
				continue
			}
			if group == 'record' && leaf == 'start' {
				region = true
				i++
				continue
			}
			return error('unknown flag: ${a}.\nExample: ${ex}')
		}
		if a == '--sound' {
			if group == 'record' && leaf == 'start' {
				sound = true
				i++
				continue
			}
			return error('unknown flag: ${a}.\nExample: ${ex}')
		}
		if a == '--sr' {
			if group == 'record' && leaf == 'start' {
				sr = true
				i++
				continue
			}
			return error('unknown flag: ${a}.\nExample: ${ex}')
		}
		if a == '--fps' {
			if group != 'record' || leaf != 'start' {
				return error('unknown flag: ${a}.\nExample: ${ex}')
			}
			if i + 1 >= rest.len || rest[i + 1].starts_with('-') {
				return error('missing value for --fps.\nExample: horneroctl capture record start --fps 60 --dry-run')
			}
			fps = rest[i + 1].int()
			if fps <= 0 {
				return error('invalid --fps value: ${rest[i + 1]} (positive integer).\nExample: horneroctl capture record start --fps 60 --dry-run')
			}
			fps_seen = true
			i += 2
			continue
		}
		if a.starts_with('--fps=') {
			if group != 'record' || leaf != 'start' {
				return error('unknown flag: ${a}.\nExample: ${ex}')
			}
			fps = a.all_after('=').int()
			if fps <= 0 {
				return error('invalid --fps value: ${a.all_after('=')} (positive integer).\nExample: horneroctl capture record start --fps 60 --dry-run')
			}
			fps_seen = true
			i++
			continue
		}
		if a == '--output' {
			if group != 'screenshot' {
				return error('unknown flag: ${a}.\nExample: ${ex}')
			}
			if i + 1 >= rest.len || rest[i + 1].starts_with('-') {
				return error('missing value for --output.\nExample: horneroctl capture screenshot --output ~/shot.png --dry-run')
			}
			output = rest[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--output=') {
			if group != 'screenshot' {
				return error('unknown flag: ${a}.\nExample: ${ex}')
			}
			output = a.all_after('=')
			if output.len == 0 {
				return error('missing value for --output.\nExample: horneroctl capture screenshot --output ~/shot.png --dry-run')
			}
			i++
			continue
		}
		if a == '--backend' {
			if group != 'clipboard' {
				return error('unknown flag: ${a}.\nExample: ${ex}')
			}
			if i + 1 >= rest.len || rest[i + 1].starts_with('-') {
				return error('missing value for --backend.\nExample: horneroctl capture clipboard --backend copyq --dry-run')
			}
			backend = rest[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--backend=') {
			if group != 'clipboard' {
				return error('unknown flag: ${a}.\nExample: ${ex}')
			}
			backend = a.all_after('=')
			if backend.len == 0 {
				return error('missing value for --backend.\nExample: horneroctl capture clipboard --backend copyq --dry-run')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: ${ex}')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl capture --help')
	}
	if group == 'screenshot' && (sound || sr || fps_seen) {
		return error('unexpected recording flag for screenshot.\nExample: horneroctl capture screenshot --dry-run')
	}
	if group == 'record' && leaf != 'start' && (region || sound || sr || fps_seen) {
		return error('record ${leaf} takes no recording flags.\nExample: horneroctl capture record ${leaf} --dry-run')
	}
	if group == 'record' && output.len > 0 {
		return error('unexpected argument: ${output}.\nRun: horneroctl capture --help')
	}
	if group == 'clipboard' && (region || fullscreen || sound || sr || fps_seen || output.len > 0) {
		return error('clipboard takes only --backend.\nExample: horneroctl capture clipboard --backend copyq --dry-run')
	}
	if backend !in ['auto', 'copyq', 'cliphist', 'minimal'] {
		return error('unknown backend: ${backend}.\nValid values: auto copyq cliphist minimal.\nExample: horneroctl capture clipboard --backend copyq --dry-run')
	}
	if group == 'clipboard' && yes {
		return error('capture clipboard needs no --yes (it only opens read views).\nExample: horneroctl capture clipboard --dry-run')
	}
	if sr {
		region = true
		sound = true
	}
	return CaptureCmdOptions{
		group:      group
		leaf:       leaf
		region:     region
		fullscreen: fullscreen
		sound:      sound
		sr:         sr
		fps:        fps
		output:     output
		backend:    backend
		dry_run:    dry_run
		yes:        yes
	}
}
