module hornero_cli

import hornero_core

pub const store_verbs = ['search', 'list', 'show', 'categories', 'collections', 'profiles',
	'profile-show', 'installed', 'install', 'remove', 'update', 'launch', 'sources', 'permissions',
	'appimage', 'webapp', 'policy', 'manifest', 'queue', 'gui', 'doctor']

pub struct StoreCmdOptions {
pub:
	verb               string
	action             string
	id                 string
	query              string
	file               string
	name               string
	url                string
	icon               string
	browser            string
	profile_dir        string
	sha256             string
	category           string
	collection         string
	profile            string
	backend            string
	source             string
	scope              string
	limit              int
	featured           bool
	verified_only      bool
	has_verified_only  bool
	verified_val       bool
	open_source_only   bool
	has_oss_only       bool
	oss_val            bool
	aur_policy         string
	proprietary_policy string
	has_allowed_srcs   bool
	allowed_sources    []string
	accept_proprietary bool
	allow_aur          bool
	all                bool
	open_flatseal      bool
	dry_run            bool
	yes                bool
}

fn store_req_val(args []string, i int, flag string, example string) !string {
	if i + 1 >= args.len {
		return error('${flag} needs a value.\nExample: ${example}')
	}
	return args[i + 1]
}

fn store_parse_bool(val string, flag string) !bool {
	v := val.trim_space().to_lower()
	if v in ['true', '1', 'yes'] {
		return true
	}
	if v in ['false', '0', 'no'] {
		return false
	}
	return error('${flag} expects true or false, got "${val}"')
}

pub fn parse_store_cmd(args []string) !StoreCmdOptions {
	if args.len == 0 {
		return error('missing store subcommand (${store_verbs.join(', ')}).\nExample: horneroctl store categories --json')
	}
	verb := args[0]
	if verb !in store_verbs {
		return error('unknown store subcommand: ${verb}.\nExample: horneroctl store search firefox --json')
	}

	mut action := ''
	mut id := ''
	mut query := ''
	mut file := ''
	mut name := ''
	mut url := ''
	mut icon := ''
	mut browser := ''
	mut profile_dir := ''
	mut sha256 := ''
	mut category := ''
	mut collection := ''
	mut profile := ''
	mut backend := ''
	mut source := ''
	mut scope := ''
	mut limit := 0
	mut featured := false
	mut verified_only := false
	mut has_verified_only := false
	mut verified_val := false
	mut open_source_only := false
	mut has_oss_only := false
	mut oss_val := false
	mut aur_policy := ''
	mut proprietary_policy := ''
	mut has_allowed_srcs := false
	mut allowed_sources := []string{}
	mut accept_proprietary := false
	mut allow_aur := false
	mut all := false
	mut open_flatseal := false
	mut dry_run := false
	mut yes := false
	mut positionals := []string{}

	mut i := 1
	for i < args.len {
		a := args[i]
		match a {
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
			'--featured' {
				featured = true
				i++
				continue
			}
			'--accept-proprietary' {
				accept_proprietary = true
				i++
				continue
			}
			'--allow-aur' {
				allow_aur = true
				i++
				continue
			}
			'--all' {
				all = true
				i++
				continue
			}
			'--open-flatseal' {
				open_flatseal = true
				i++
				continue
			}
			'--verified-only' {
				if verb == 'policy' {
					v := store_req_val(args, i, '--verified-only', 'horneroctl store policy set --verified-only true --yes')!
					verified_val = store_parse_bool(v, '--verified-only')!
					has_verified_only = true
					i += 2
				} else {
					verified_only = true
					i++
				}
				continue
			}
			'--open-source-only' {
				if verb == 'policy' {
					v := store_req_val(args, i, '--open-source-only', 'horneroctl store policy set --open-source-only true --yes')!
					oss_val = store_parse_bool(v, '--open-source-only')!
					has_oss_only = true
					i += 2
				} else {
					open_source_only = true
					i++
				}
				continue
			}
			'--category' {
				category = store_req_val(args, i, '--category', 'horneroctl store list --category browsers')!
				i += 2
				continue
			}
			'--collection' {
				collection = store_req_val(args, i, '--collection', 'horneroctl store list --collection ai-workstation')!
				i += 2
				continue
			}
			'--profile' {
				profile = store_req_val(args, i, '--profile', 'horneroctl store list --profile ai-native-workstation')!
				i += 2
				continue
			}
			'--backend' {
				backend = store_req_val(args, i, '--backend', 'horneroctl store installed --backend flatpak')!
				i += 2
				continue
			}
			'--source' {
				source = store_req_val(args, i, '--source', 'horneroctl store install firefox --source flatpak --dry-run')!
				i += 2
				continue
			}
			'--scope' {
				scope = store_req_val(args, i, '--scope', 'horneroctl store install firefox --source flatpak --scope user --dry-run')!
				i += 2
				continue
			}
			'--limit' {
				raw := store_req_val(args, i, '--limit', 'horneroctl store list --limit 20')!
				limit = raw.int()
				if limit <= 0 {
					return error('--limit must be a positive integer.\nExample: horneroctl store list --limit 20')
				}
				i += 2
				continue
			}
			'--id' {
				id = store_req_val(args, i, '--id', 'horneroctl store appimage import ./app.AppImage --id my-app --yes')!
				i += 2
				continue
			}
			'--name' {
				name = store_req_val(args, i, '--name', 'horneroctl store webapp add github --name GitHub --url https://github.com --yes')!
				i += 2
				continue
			}
			'--url' {
				url = store_req_val(args, i, '--url', 'horneroctl store webapp add github --name GitHub --url https://github.com --yes')!
				i += 2
				continue
			}
			'--icon' {
				icon = store_req_val(args, i, '--icon', 'horneroctl store webapp add github --icon web-browser --url https://github.com --yes')!
				i += 2
				continue
			}
			'--browser' {
				browser = store_req_val(args, i, '--browser', 'horneroctl store webapp add github --browser chromium --url https://github.com --yes')!
				i += 2
				continue
			}
			'--profile-dir' {
				profile_dir = store_req_val(args, i, '--profile-dir', 'horneroctl store webapp add github --profile-dir ~/.local/share/hornero/webapps/github --url https://github.com --yes')!
				i += 2
				continue
			}
			'--sha256' {
				sha256 = store_req_val(args, i, '--sha256', 'horneroctl store appimage import ./app.AppImage --id my-app --sha256 <hex> --yes')!
				i += 2
				continue
			}
			'--aur-policy' {
				aur_policy = store_req_val(args, i, '--aur-policy', 'horneroctl store policy set --aur-policy disabled --yes')!
				i += 2
				continue
			}
			'--proprietary-policy' {
				proprietary_policy = store_req_val(args, i, '--proprietary-policy', 'horneroctl store policy set --proprietary-policy opt-in --yes')!
				i += 2
				continue
			}
			'--allowed-sources' {
				raw := store_req_val(args, i, '--allowed-sources', 'horneroctl store policy set --allowed-sources arch_native,flatpak --yes')!
				has_allowed_srcs = true
				for part in raw.split(',') {
					t := part.trim_space()
					if t.len > 0 {
						allowed_sources << t
					}
				}
				i += 2
				continue
			}
			else {}
		}
		if a.starts_with('-') {
			return error('unknown flag for store ${verb}: ${a}.\nExample: horneroctl store ${verb} --help')
		}
		positionals << a
		i++
	}

	match verb {
		'search' {
			if positionals.len > 0 {
				query = positionals.join(' ')
			}
		}
		'show', 'profile-show', 'install', 'remove', 'launch', 'permissions' {
			if positionals.len != 1 {
				return error('expected <id>.\nExample: horneroctl store ${verb} firefox')
			}
			id = positionals[0]
		}
		'update' {
			if positionals.len > 1 {
				return error('unexpected argument: ${positionals[1]}.\nExample: horneroctl store update --all --dry-run')
			}
			if positionals.len == 1 {
				id = positionals[0]
			}
			if id.len == 0 && !all && backend.len == 0 {
				return error('specify <id> or --all.\nExample: horneroctl store update --all --dry-run')
			}
		}
		'gui' {
			if positionals.len > 1 {
				return error('unexpected argument: ${positionals[1]}.\nExample: horneroctl store gui firefox --dry-run')
			}
			if positionals.len == 1 {
				id = positionals[0]
			}
		}
		'categories', 'collections', 'profiles', 'sources', 'doctor', 'list', 'installed' {
			if positionals.len > 0 {
				return error('unexpected argument: ${positionals[0]}.\nExample: horneroctl store ${verb} --json')
			}
		}
		'appimage' {
			if positionals.len == 0 {
				return error('expected appimage action (list|import|remove).\nExample: horneroctl store appimage list --json')
			}
			action = positionals[0]
			if action !in ['list', 'import', 'remove'] {
				return error('unknown appimage action: ${action}.\nExample: horneroctl store appimage list')
			}
			if action == 'import' {
				if positionals.len < 2 {
					return error('expected <file>.\nExample: horneroctl store appimage import ./app.AppImage --id my-app --dry-run')
				}
				file = positionals[1]
				if id.len == 0 {
					id = hornero_core.slugify_appimage_id(file)
				}
			} else if action == 'remove' {
				if positionals.len < 2 && id.len == 0 {
					return error('expected <id>.\nExample: horneroctl store appimage remove my-app --dry-run')
				}
				if positionals.len >= 2 {
					id = positionals[1]
				}
			}
		}
		'webapp' {
			if positionals.len == 0 {
				return error('expected webapp action (list|add|remove).\nExample: horneroctl store webapp list --json')
			}
			action = positionals[0]
			if action !in ['list', 'add', 'remove'] {
				return error('unknown webapp action: ${action}.\nExample: horneroctl store webapp list')
			}
			if action == 'add' {
				if positionals.len >= 2 {
					id = positionals[1]
				}
				if id.len == 0 || url.len == 0 {
					return error('expected <id> and --url.\nExample: horneroctl store webapp add github --name GitHub --url https://github.com --dry-run')
				}
				if name.len == 0 {
					name = id
				}
			} else if action == 'remove' {
				if positionals.len >= 2 {
					id = positionals[1]
				}
				if id.len == 0 {
					return error('expected <id>.\nExample: horneroctl store webapp remove github --dry-run')
				}
			}
		}
		'policy' {
			action = if positionals.len > 0 { positionals[0] } else { 'show' }
			if action !in ['show', 'set', 'reset'] {
				return error('unknown policy action: ${action} (expected: show, set, reset).\nExample: horneroctl store policy show --json')
			}
		}
		'manifest' {
			if positionals.len < 2 {
				return error('expected <export|import|apply> <file>.\nExample: horneroctl store manifest export ./apps.json --dry-run')
			}
			action = positionals[0]
			if action !in ['export', 'import', 'apply'] {
				return error('unknown manifest action: ${action} (expected: export, import, apply).\nExample: horneroctl store manifest export ./apps.json --dry-run')
			}
			file = positionals[1]
		}
		'queue' {
			action = if positionals.len > 0 { positionals[0] } else { 'list' }
			if action !in ['list', 'add', 'remove', 'run', 'clear'] {
				return error('unknown queue action: ${action} (expected: list, add, remove, run, clear).\nExample: horneroctl store queue list --json')
			}
			if action in ['add', 'remove'] {
				if positionals.len >= 2 {
					id = positionals[1]
				}
				if id.len == 0 {
					return error('expected <id>.\nExample: horneroctl store queue ${action} firefox --dry-run')
				}
			}
		}
		else {}
	}

	return StoreCmdOptions{
		verb:               verb
		action:             action
		id:                 id
		query:              query
		file:               file
		name:               name
		url:                url
		icon:               icon
		browser:            browser
		profile_dir:        profile_dir
		sha256:             sha256
		category:           category
		collection:         collection
		profile:            profile
		backend:            backend
		source:             source
		scope:              scope
		limit:              limit
		featured:           featured
		verified_only:      verified_only
		has_verified_only:  has_verified_only
		verified_val:       verified_val
		open_source_only:   open_source_only
		has_oss_only:       has_oss_only
		oss_val:            oss_val
		aur_policy:         aur_policy
		proprietary_policy: proprietary_policy
		has_allowed_srcs:   has_allowed_srcs
		allowed_sources:    allowed_sources
		accept_proprietary: accept_proprietary
		allow_aur:          allow_aur
		all:                all
		open_flatseal:      open_flatseal
		dry_run:            dry_run
		yes:                yes
	}
}
