module hornero_cli

import hornero_core

// Hardware option parsers: `hardware <brightness|battery|mic|keyboard|
// network> ...`. Error strings always carry a correct Example (exit-2
// contract). Reads accept --dry-run (they exec a probe backend);
// mutating leaves also need --yes.

// hw_take_value consumes a `--name value` or `--name=value` flag at
// position i, returning the value and the next position.
fn hw_take_value(args []string, i int, name string, example string) !(string, int) {
	a := args[i]
	eq := '--${name}='
	if a.starts_with(eq) {
		return a[eq.len..], i + 1
	}
	if a == '--${name}' {
		if i + 1 < args.len && !args[i + 1].starts_with('-') {
			return args[i + 1], i + 2
		}
		return error('missing value for --${name}.\nExample: ${example}')
	}
	return error('unreachable flag parse')
}

fn hw_is_int(s string) bool {
	if s.len == 0 {
		return false
	}
	for c in s {
		if c < `0` || c > `9` {
			return false
		}
	}
	return true
}

// HardwareBrightnessOptions covers
// `hardware brightness <status|set|up|down>`.
pub struct HardwareBrightnessOptions {
pub:
	leaf    string // status | set | up | down
	display string
	value   f64
	step    f64
	dry_run bool
	yes     bool
}

pub fn parse_hardware_brightness(args []string) !HardwareBrightnessOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hardware brightness status')
	}
	leaf := args[0]
	if leaf !in ['status', 'set', 'up', 'down'] {
		return error('unknown brightness subcommand: ${leaf}.\nRun: horneroctl hardware brightness --help')
	}
	mut display := ''
	mut value := 0.0
	mut step := 0.1
	mut dry_run := false
	mut yes := false
	mut positional := []string{}
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
		if a == '--display' || a.starts_with('--display=') {
			v, ni := hw_take_value(args, i, 'display', 'horneroctl hardware brightness status --display eDP-1')!
			display = v
			i = ni
			continue
		}
		if a == '--step' || a.starts_with('--step=') {
			v, ni := hw_take_value(args, i, 'step', 'horneroctl hardware brightness up --step 0.05 --dry-run')!
			if !hornero_core.is_decimal_number(v) {
				return error('invalid step: ${v} (use a 0.0-1.0 fraction).\nExample: horneroctl hardware brightness up --step 0.05 --dry-run')
			}
			step = v.f64()
			if step <= 0.0 {
				return error('invalid step: ${v} (must be positive).\nExample: horneroctl hardware brightness up --step 0.05 --dry-run')
			}
			i = ni
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hardware brightness ${leaf} --dry-run')
		}
		positional << a
		i++
	}
	if leaf == 'status' {
		if positional.len > 0 {
			return error('unexpected argument: ${positional[0]}.\nRun: horneroctl hardware brightness --help')
		}
		if step != 0.1 {
			return error('brightness status takes no --step.\nExample: horneroctl hardware brightness status')
		}
		if yes {
			return error('brightness status takes no --yes (it only reads).\nExample: horneroctl hardware brightness status')
		}
	}
	if leaf == 'set' {
		if positional.len == 0 {
			return error('missing value (0.0-1.0 fraction).\nExample: horneroctl hardware brightness set 0.8 --dry-run')
		}
		if positional.len > 1 {
			return error('unexpected argument: ${positional[1]}.\nRun: horneroctl hardware brightness --help')
		}
		if !hornero_core.is_decimal_number(positional[0]) {
			return error('invalid value: ${positional[0]} (use a 0.0-1.0 fraction).\nExample: horneroctl hardware brightness set 0.8 --dry-run')
		}
		value = positional[0].f64()
		if step != 0.1 {
			return error('brightness set takes no --step.\nExample: horneroctl hardware brightness set 0.8 --dry-run')
		}
	}
	if leaf in ['up', 'down'] {
		if positional.len > 0 {
			return error('unexpected argument: ${positional[0]}.\nRun: horneroctl hardware brightness --help')
		}
	}
	return HardwareBrightnessOptions{
		leaf:    leaf
		display: display
		value:   value
		step:    step
		dry_run: dry_run
		yes:     yes
	}
}

// HardwareBatteryOptions covers `hardware battery <status|monitor>`.
pub struct HardwareBatteryOptions {
pub:
	leaf     string // status | monitor
	low      int
	crit     int
	interval i64
	daemon   bool
	dry_run  bool
	yes      bool
}

pub fn parse_hardware_battery(args []string) !HardwareBatteryOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hardware battery status')
	}
	leaf := args[0]
	if leaf !in ['status', 'monitor'] {
		return error('unknown battery subcommand: ${leaf}.\nRun: horneroctl hardware battery --help')
	}
	mut low := 20
	mut crit := 10
	mut interval := i64(120)
	mut daemon := false
	mut dry_run := false
	mut yes := false
	mut saw_monitor_flag := false
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
		if a == '--daemon' {
			daemon = true
			saw_monitor_flag = true
			i++
			continue
		}
		if a == '--low' || a.starts_with('--low=') {
			v, ni := hw_take_value(args, i, 'low', 'horneroctl hardware battery monitor --low=25 --dry-run')!
			if !hw_is_int(v) {
				return error('invalid --low: ${v} (use a 0-100 percent).\nExample: horneroctl hardware battery monitor --low=25 --dry-run')
			}
			low = v.int()
			saw_monitor_flag = true
			i = ni
			continue
		}
		if a == '--crit' || a.starts_with('--crit=') {
			v, ni := hw_take_value(args, i, 'crit', 'horneroctl hardware battery monitor --crit=15 --dry-run')!
			if !hw_is_int(v) {
				return error('invalid --crit: ${v} (use a 0-100 percent).\nExample: horneroctl hardware battery monitor --crit=15 --dry-run')
			}
			crit = v.int()
			saw_monitor_flag = true
			i = ni
			continue
		}
		if a == '--interval' || a.starts_with('--interval=') {
			v, ni := hw_take_value(args, i, 'interval', 'horneroctl hardware battery monitor --interval=60 --dry-run')!
			if !hw_is_int(v) {
				return error('invalid --interval: ${v} (use seconds >= 1).\nExample: horneroctl hardware battery monitor --interval=60 --dry-run')
			}
			interval = i64(v.int())
			saw_monitor_flag = true
			i = ni
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hardware battery ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hardware battery --help')
	}
	if leaf == 'status' {
		if saw_monitor_flag {
			return error('battery status takes no thresholds (see monitor).\nExample: horneroctl hardware battery status')
		}
		if yes {
			return error('battery status takes no --yes (it only reads).\nExample: horneroctl hardware battery status')
		}
		return HardwareBatteryOptions{
			leaf:     leaf
			low:      low
			crit:     crit
			interval: interval
			daemon:   false
			dry_run:  dry_run
			yes:      false
		}
	}
	if low < 0 || low > 100 {
		return error('invalid --low: ${low} (use a 0-100 percent).\nExample: horneroctl hardware battery monitor --low=25 --dry-run')
	}
	if crit < 0 || crit > 100 {
		return error('invalid --crit: ${crit} (use a 0-100 percent).\nExample: horneroctl hardware battery monitor --crit=15 --dry-run')
	}
	if crit > low {
		return error('invalid thresholds: --crit (${crit}) must not exceed --low (${low}).\nExample: horneroctl hardware battery monitor --low=25 --crit=15 --dry-run')
	}
	if interval < 1 {
		return error('invalid --interval: ${interval} (use seconds >= 1).\nExample: horneroctl hardware battery monitor --interval=60 --dry-run')
	}
	return HardwareBatteryOptions{
		leaf:     leaf
		low:      low
		crit:     crit
		interval: interval
		daemon:   daemon
		dry_run:  dry_run
		yes:      yes
	}
}

// HardwareMicOptions covers `hardware mic <status|toggle>`.
pub struct HardwareMicOptions {
pub:
	leaf    string // status | toggle
	dry_run bool
	yes     bool
}

pub fn parse_hardware_mic(args []string) !HardwareMicOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hardware mic status')
	}
	leaf := args[0]
	if leaf !in ['status', 'toggle'] {
		return error('unknown mic subcommand: ${leaf}.\nRun: horneroctl hardware mic --help')
	}
	mut dry_run := false
	mut yes := false
	for i := 1; i < args.len; i++ {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a == '--yes' {
			yes = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hardware mic ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hardware mic --help')
	}
	if leaf == 'status' && yes {
		return error('mic status takes no --yes (it only reads).\nExample: horneroctl hardware mic status')
	}
	return HardwareMicOptions{
		leaf:    leaf
		dry_run: dry_run
		yes:     yes
	}
}

// HardwareKeyboardOptions covers
// `hardware keyboard <layout|settings|keys>`.
pub struct HardwareKeyboardOptions {
pub:
	leaf     string // layout | settings | keys
	current  bool
	get      bool
	toggle   bool
	category string
	search   string
	dry_run  bool
	yes      bool
}

pub fn parse_hardware_keyboard(args []string) !HardwareKeyboardOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hardware keyboard layout --current')
	}
	leaf := args[0]
	if leaf !in ['layout', 'settings', 'keys'] {
		return error('unknown keyboard subcommand: ${leaf}.\nRun: horneroctl hardware keyboard --help')
	}
	mut current := false
	mut get := false
	mut toggle := false
	mut category := ''
	mut search := ''
	mut dry_run := false
	mut yes := false
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
		if a in ['--current', '-c'] {
			current = true
			i++
			continue
		}
		if a in ['--get', '-g'] {
			get = true
			i++
			continue
		}
		if a in ['--toggle', '-t'] {
			toggle = true
			i++
			continue
		}
		if a == '--category' || a.starts_with('--category=') {
			v, ni := hw_take_value(args, i, 'category', 'horneroctl hardware keyboard keys --category=Window')!
			category = v
			i = ni
			continue
		}
		if a == '--search' || a.starts_with('--search=') {
			v, ni := hw_take_value(args, i, 'search', 'horneroctl hardware keyboard keys --search=workspace')!
			search = v
			i = ni
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hardware keyboard ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hardware keyboard --help')
	}
	if leaf == 'layout' {
		if category.len > 0 || search.len > 0 {
			return error('keyboard layout takes no --category/--search (see keys).\nExample: horneroctl hardware keyboard layout --current')
		}
		if current && get {
			return error('pick one of --current or --get.\nExample: horneroctl hardware keyboard layout --current')
		}
		return HardwareKeyboardOptions{
			leaf:    leaf
			current: current
			get:     get
			toggle:  toggle
			dry_run: dry_run
			yes:     yes
		}
	}
	if current || get || toggle {
		return error('keyboard ${leaf} takes no layout flags.\nExample: horneroctl hardware keyboard ${leaf} --dry-run')
	}
	if yes {
		return error('keyboard ${leaf} takes no --yes.\nExample: horneroctl hardware keyboard ${leaf} --dry-run')
	}
	if leaf == 'settings' && (category.len > 0 || search.len > 0) {
		return error('keyboard settings takes no --category/--search (see keys).\nExample: horneroctl hardware keyboard settings --dry-run')
	}
	return HardwareKeyboardOptions{
		leaf:     leaf
		category: category
		search:   search
		dry_run:  dry_run
		yes:      false
	}
}

// HardwareNetworkOptions covers `hardware network status`.
pub struct HardwareNetworkOptions {
pub:
	leaf    string // status
	timeout int
	dry_run bool
}

pub fn parse_hardware_network(args []string) !HardwareNetworkOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hardware network status')
	}
	leaf := args[0]
	if leaf != 'status' {
		return error('unknown network subcommand: ${leaf}.\nRun: horneroctl hardware network --help')
	}
	mut timeout := 5
	mut dry_run := false
	mut i := 1
	for i < args.len {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a == '--timeout' || a.starts_with('--timeout=') {
			v, ni := hw_take_value(args, i, 'timeout', 'horneroctl hardware network status --timeout=2')!
			if !hw_is_int(v) || v.int() < 1 {
				return error('invalid --timeout: ${v} (use seconds >= 1).\nExample: horneroctl hardware network status --timeout=2')
			}
			timeout = v.int()
			i = ni
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hardware network status --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hardware network --help')
	}
	return HardwareNetworkOptions{
		leaf:    leaf
		timeout: timeout
		dry_run: dry_run
	}
}
