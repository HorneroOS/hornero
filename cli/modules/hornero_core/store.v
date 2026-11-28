module hornero_core

import os
import x.json2

// Canonical Verified Application Store Engine (`horneroctl store`).
//
// Pure domain logic: loads the canonical catalog (`catalog/apps.v1.json` via
// HORNERO_APP_CATALOG -> $XDG_DATA_HOME/hornero/catalog/apps.v1.json ->
// /usr/share/hornero/catalog/apps.v1.json -> repo fallback -> embedded),
// enforces policy gates, executes safe literal-argv backend operations, and
// manages declarative manifests & onboarding queues.

const embedded_app_catalog_json = $embed_file('../../../catalog/apps.v1.json').to_string()

pub struct StoreSource {
pub:
	backend               string
	provenance            string
	package_id            string
	remote                string
	verified              bool
	maintainer            string
	signature_available   bool
	update_mechanism      string
	scope                 string
	sandboxed             bool
	recommended_reason    string
	recommended_reason_es string
}

pub struct StoreApp {
pub:
	id                 string
	name               string
	aliases            []string
	summary            string
	summary_es         string
	description        string
	description_es     string
	category           string
	tags               []string
	collections        []string
	profiles           []string
	featured           bool
	priority           int
	publisher          string
	homepage           string
	repository         string
	support_url        string
	icon               string
	license            string
	is_open_source     bool
	pricing            string
	requires_account   bool
	architectures      []string
	wayland_support    string
	gpu_requirement    string
	hardware_notes     string
	stability          string
	status             string
	recommended_source string
	sources            []StoreSource
	permissions_note   string
	known_limitations  string
	last_verified      string
	deprecated         bool
}

pub struct StoreCategory {
pub:
	id             string
	name           string
	name_es        string
	description    string
	description_es string
	icon           string
	order          int
}

pub struct StoreCollection {
pub:
	id             string
	name           string
	name_es        string
	description    string
	description_es string
	icon           string
	apps           []string
}

pub struct StoreProfile {
pub:
	id                 string
	name               string
	name_es            string
	description        string
	description_es     string
	apps               []string
	proprietary_opt_in []string
}

pub struct AppCatalog {
pub:
	api_version    string
	kind           string
	schema_version int
	verified_at    string
	categories     []StoreCategory
	collections    []StoreCollection
	profiles       []StoreProfile
	apps           []StoreApp
	source_path    string
}

pub struct StoreAppView {
pub:
	id                 string
	name               string
	summary            string
	summary_es         string
	category           string
	featured           bool
	publisher          string
	icon               string
	license            string
	is_open_source     bool
	status             string
	stability          string
	recommended_source string
	installed          bool
	installed_via      string
	policy_allowed     bool
	policy_reason      string
	sources            []StoreSource
}

pub struct StoreCategorySummary {
pub:
	id      string
	name    string
	name_es string
	icon    string
	order   int
	count   int
}

pub struct StoreCollectionSummary {
pub:
	id           string
	name         string
	name_es      string
	description  string
	icon         string
	count        int
	preview_apps []string
}

pub struct StoreProfileSummary {
pub:
	id                       string
	name                     string
	name_es                  string
	description              string
	app_count                int
	proprietary_opt_in_count int
	installed_count          int
}

pub struct StoreSearchOptions {
pub:
	query            string
	category         string
	backend          string
	verified_only    bool
	open_source_only bool
}

pub struct StoreListOptions {
pub:
	category   string
	collection string
	profile    string
	featured   bool
	limit      int
}

pub struct StoreInstallOptions {
pub:
	id                 string
	source             string
	scope              string
	accept_proprietary bool
	allow_aur          bool
	dry_run            bool
	yes                bool
}

pub struct StoreRemoveOptions {
pub:
	id      string
	source  string
	dry_run bool
	yes     bool
}

pub struct StoreUpdateOptions {
pub:
	id      string
	all     bool
	backend string
	dry_run bool
	yes     bool
}

pub struct StoreManifestDoc {
pub:
	api_version string @[json: 'apiVersion']
	kind        string
	schema      int @[json: 'schemaVersion']
	policy      StorePolicyDisk
	apps        []string
}

pub struct StoreQueueItem {
pub:
	id      string
	backend string
}

pub struct StoreQueueDoc {
pub mut:
	items []StoreQueueItem
}

fn j_str(m map[string]json2.Any, key string) string {
	val := m[key] or { return '' }
	if val is json2.Null {
		return ''
	}
	return val.str()
}

fn j_bool(m map[string]json2.Any, key string) bool {
	val := m[key] or { return false }
	return val.bool()
}

fn j_int(m map[string]json2.Any, key string) int {
	val := m[key] or { return 0 }
	return val.int()
}

fn j_str_list(m map[string]json2.Any, key string) []string {
	val := m[key] or { return []string{} }
	if val !is []json2.Any {
		return []string{}
	}
	mut out := []string{}
	for item in val.as_array() {
		out << item.str()
	}
	return out
}

// resolve_app_catalog_path locates the catalog JSON on disk, or returns 'embedded'.
pub fn resolve_app_catalog_path() string {
	env := os.getenv('HORNERO_APP_CATALOG').trim_space()
	if env.len > 0 {
		return env
	}
	xdg := os.join_path(resolve_paths().data_dir, 'hornero', 'catalog', 'apps.v1.json')
	if os.is_file(xdg) {
		return xdg
	}
	sys := '/usr/share/hornero/catalog/apps.v1.json'
	if os.is_file(sys) {
		return sys
	}
	mut dir := os.getwd()
	for _ in 0 .. 5 {
		candidate := os.join_path(dir, 'catalog', 'apps.v1.json')
		if os.is_file(candidate) {
			return candidate
		}
		parent := os.dir(dir)
		if parent == dir || parent.len == 0 {
			break
		}
		dir = parent
	}
	return 'embedded'
}

// load_app_catalog loads and parses the canonical verified application catalog.
pub fn load_app_catalog() !AppCatalog {
	path := resolve_app_catalog_path()
	raw := if path == 'embedded' {
		embedded_app_catalog_json
	} else {
		os.read_file(path) or { return error('cannot read app catalog ${path}: ${err.msg()}') }
	}
	return parse_app_catalog(raw, path)
}

pub fn parse_app_catalog(raw string, source_path string) !AppCatalog {
	decoded := json2.decode[json2.Any](raw) or {
		return error('invalid app catalog JSON (${source_path}): ${err.msg()}')
	}
	root := decoded.as_map()
	api_ver := j_str(root, 'apiVersion')
	kind := j_str(root, 'kind')
	schema_ver := j_int(root, 'schemaVersion')
	if api_ver != 'hornero.os/v1' || kind != 'ApplicationCatalog' || schema_ver != 1 {
		return error('unsupported app catalog envelope: ${api_ver} ${kind} v${schema_ver}')
	}
	mut categories := []StoreCategory{}
	if cats_any := root['categories'] {
		for item in cats_any.as_array() {
			m := item.as_map()
			categories << StoreCategory{
				id:             j_str(m, 'id')
				name:           j_str(m, 'name')
				name_es:        j_str(m, 'name_es')
				description:    j_str(m, 'description')
				description_es: j_str(m, 'description_es')
				icon:           j_str(m, 'icon')
				order:          j_int(m, 'order')
			}
		}
	}
	mut collections := []StoreCollection{}
	if cols_any := root['collections'] {
		for item in cols_any.as_array() {
			m := item.as_map()
			collections << StoreCollection{
				id:             j_str(m, 'id')
				name:           j_str(m, 'name')
				name_es:        j_str(m, 'name_es')
				description:    j_str(m, 'description')
				description_es: j_str(m, 'description_es')
				icon:           j_str(m, 'icon')
				apps:           j_str_list(m, 'apps')
			}
		}
	}
	mut profiles := []StoreProfile{}
	if profs_any := root['profiles'] {
		for item in profs_any.as_array() {
			m := item.as_map()
			profiles << StoreProfile{
				id:                 j_str(m, 'id')
				name:               j_str(m, 'name')
				name_es:            j_str(m, 'name_es')
				description:        j_str(m, 'description')
				description_es:     j_str(m, 'description_es')
				apps:               j_str_list(m, 'apps')
				proprietary_opt_in: j_str_list(m, 'proprietaryOptIn')
			}
		}
	}
	mut apps := []StoreApp{}
	if apps_any := root['apps'] {
		for item in apps_any.as_array() {
			m := item.as_map()
			mut srcs := []StoreSource{}
			if srcs_any := m['sources'] {
				for sitem in srcs_any.as_array() {
					sm := sitem.as_map()
					srcs << StoreSource{
						backend:               j_str(sm, 'backend')
						provenance:            j_str(sm, 'provenance')
						package_id:            j_str(sm, 'package_id')
						remote:                j_str(sm, 'remote')
						verified:              j_bool(sm, 'verified')
						maintainer:            j_str(sm, 'maintainer')
						signature_available:   j_bool(sm, 'signature_available')
						update_mechanism:      j_str(sm, 'update_mechanism')
						scope:                 j_str(sm, 'scope')
						sandboxed:             j_bool(sm, 'sandboxed')
						recommended_reason:    j_str(sm, 'recommended_reason')
						recommended_reason_es: j_str(sm, 'recommended_reason_es')
					}
				}
			}
			apps << StoreApp{
				id:                 j_str(m, 'id')
				name:               j_str(m, 'name')
				aliases:            j_str_list(m, 'aliases')
				summary:            j_str(m, 'summary')
				summary_es:         j_str(m, 'summary_es')
				description:        j_str(m, 'description')
				description_es:     j_str(m, 'description_es')
				category:           j_str(m, 'category')
				tags:               j_str_list(m, 'tags')
				collections:        j_str_list(m, 'collections')
				profiles:           j_str_list(m, 'profiles')
				featured:           j_bool(m, 'featured')
				priority:           j_int(m, 'priority')
				publisher:          j_str(m, 'publisher')
				homepage:           j_str(m, 'homepage')
				repository:         j_str(m, 'repository')
				support_url:        j_str(m, 'support_url')
				icon:               j_str(m, 'icon')
				license:            j_str(m, 'license')
				is_open_source:     j_bool(m, 'is_open_source')
				pricing:            j_str(m, 'pricing')
				requires_account:   j_bool(m, 'requires_account')
				architectures:      j_str_list(m, 'architectures')
				wayland_support:    j_str(m, 'wayland_support')
				gpu_requirement:    j_str(m, 'gpu_requirement')
				hardware_notes:     j_str(m, 'hardware_notes')
				stability:          j_str(m, 'stability')
				status:             j_str(m, 'status')
				recommended_source: j_str(m, 'recommended_source')
				sources:            srcs
				permissions_note:   j_str(m, 'permissions_note')
				known_limitations:  j_str(m, 'known_limitations')
				last_verified:      j_str(m, 'last_verified')
				deprecated:         j_bool(m, 'deprecated')
			}
		}
	}
	return AppCatalog{
		api_version:    api_ver
		kind:           kind
		schema_version: schema_ver
		verified_at:    j_str(root, 'verifiedAt')
		categories:     categories
		collections:    collections
		profiles:       profiles
		apps:           apps
		source_path:    source_path
	}
}

pub fn find_catalog_app(cat AppCatalog, id string) ?StoreApp {
	q := id.trim_space().to_lower()
	for a in cat.apps {
		if a.id == q {
			return a
		}
	}
	for a in cat.apps {
		if q in a.aliases {
			return a
		}
	}
	return none
}

fn select_source(app StoreApp, requested string) !StoreSource {
	if app.sources.len == 0 {
		return error('application "${app.id}" has no installable sources (${app.status})')
	}
	target := if requested.len > 0 { requested } else { app.recommended_source }
	for s in app.sources {
		if s.backend == target {
			return s
		}
	}
	available := app.sources.map(it.backend).join(', ')
	return error('source "${target}" not available for "${app.id}" (available: ${available})')
}

fn build_app_view(app StoreApp, snap StoreInstalledSnapshot, pol StorePolicy) StoreAppView {
	installed, via := app_install_status(app, snap)
	mut allowed := false
	mut reason := 'no installable sources'
	if src := select_source(app, '') {
		allowed, reason = evaluate_store_policy(app, src, pol, false, false)
	}
	return StoreAppView{
		id:                 app.id
		name:               app.name
		summary:            app.summary
		summary_es:         app.summary_es
		category:           app.category
		featured:           app.featured
		publisher:          app.publisher
		icon:               app.icon
		license:            app.license
		is_open_source:     app.is_open_source
		status:             app.status
		stability:          app.stability
		recommended_source: app.recommended_source
		installed:          installed
		installed_via:      via
		policy_allowed:     allowed
		policy_reason:      reason
		sources:            app.sources
	}
}

pub fn store_search_result(opts StoreSearchOptions) CommandResult {
	cmd := 'store search'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	snap := detect_installed_snapshot()
	pol := load_store_policy()
	q := opts.query.trim_space().to_lower()

	mut views := []StoreAppView{}
	for a in cat.apps {
		if opts.category.len > 0 && a.category != opts.category {
			continue
		}
		if opts.open_source_only && !a.is_open_source {
			continue
		}
		if opts.backend.len > 0 && !a.sources.any(it.backend == opts.backend) {
			continue
		}
		if opts.verified_only && !a.sources.any(it.verified) {
			continue
		}
		if q.len > 0 {
			haystack := '${a.id} ${a.name} ${a.summary} ${a.aliases.join(' ')} ${a.tags.join(' ')}'.to_lower()
			if !haystack.contains(q) {
				continue
			}
		}
		views << build_app_view(a, snap, pol)
	}
	mut lines := []string{}
	for v in views {
		badge := if v.installed {
			'[installed:${v.installed_via}]'
		} else {
			'[${v.recommended_source}]'
		}
		lines << '${v.id:-26s}  ${v.name:-28s}  ${badge}  ${v.summary}'
	}
	if views.len == 0 {
		lines << 'No matching applications found.'
	}
	return ok_result(cmd, lines.join('\n'), {
		'query': opts.query
		'count': views.len.str()
		'apps':  json2.encode(views, escape_unicode: true)
	})
}

pub fn store_list_result(opts StoreListOptions) CommandResult {
	cmd := 'store list'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	snap := detect_installed_snapshot()
	pol := load_store_policy()

	mut col_apps := []string{}
	mut filter_col := false
	if opts.collection.len > 0 {
		filter_col = true
		for c in cat.collections {
			if c.id == opts.collection {
				col_apps = c.apps.clone()
				break
			}
		}
		if col_apps.len == 0 {
			return fail_result(cmd, 'unknown collection: ${opts.collection}')
		}
	}

	mut prof_apps := []string{}
	mut filter_prof := false
	if opts.profile.len > 0 {
		filter_prof = true
		for p in cat.profiles {
			if p.id == opts.profile {
				prof_apps << p.apps
				prof_apps << p.proprietary_opt_in
				break
			}
		}
		if prof_apps.len == 0 {
			return fail_result(cmd, 'unknown profile: ${opts.profile}')
		}
	}

	mut matched := []StoreAppView{}
	for a in cat.apps {
		if opts.category.len > 0 && a.category != opts.category {
			continue
		}
		if opts.featured && !a.featured {
			continue
		}
		if filter_col && a.id !in col_apps {
			continue
		}
		if filter_prof && a.id !in prof_apps {
			continue
		}
		matched << build_app_view(a, snap, pol)
	}
	total := matched.len
	if opts.limit > 0 && matched.len > opts.limit {
		matched = matched[..opts.limit]
	}
	mut lines := []string{}
	for v in matched {
		lines << '${v.id:-26s}  ${v.name:-28s}  ${v.category:-16s}  ${v.recommended_source}'
	}
	if matched.len == 0 {
		lines << 'No applications matched the filters.'
	}
	return ok_result(cmd, lines.join('\n'), {
		'count': matched.len.str()
		'total': total.str()
		'apps':  json2.encode(matched, escape_unicode: true)
	})
}

pub fn store_show_result(id string) CommandResult {
	cmd := 'store show'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	app := find_catalog_app(cat, id) or {
		return fail_result(cmd, 'application not found in catalog: ${id}')
	}
	snap := detect_installed_snapshot()
	pol := load_store_policy()
	view := build_app_view(app, snap, pol)
	mut lines := [
		'${app.name} (${app.id})',
		'  Category:    ${app.category}',
		'  Publisher:   ${app.publisher}',
		'  License:     ${app.license} (open_source=${app.is_open_source})',
		'  Status:      ${app.status} (${app.stability})',
		'  Installed:   ${view.installed}${if view.installed {
			' via ' + view.installed_via
		} else {
			''
		}}',
		'  Recommended: ${app.recommended_source}',
		'  Homepage:    ${app.homepage}',
		'  Summary:     ${app.summary}',
		'  Sources:',
	]
	for s in app.sources {
		lines << '    - ${s.backend} (${s.provenance}, verified=${s.verified}): ${s.package_id} — ${s.recommended_reason}'
	}
	if app.known_limitations.len > 0 {
		lines << '  Notes:       ${app.known_limitations}'
	}
	return ok_result(cmd, lines.join('\n'), {
		'id':             app.id
		'installed':      view.installed.str()
		'installed_via':  view.installed_via
		'policy_allowed': view.policy_allowed.str()
		'policy_reason':  view.policy_reason
		'app':            json2.encode(view, escape_unicode: true)
	})
}

pub fn store_categories_result() CommandResult {
	cmd := 'store categories'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	mut summaries := []StoreCategorySummary{}
	mut lines := []string{}
	for c in cat.categories {
		count := cat.apps.filter(it.category == c.id).len
		summaries << StoreCategorySummary{
			id:      c.id
			name:    c.name
			name_es: c.name_es
			icon:    c.icon
			order:   c.order
			count:   count
		}
		lines << '${c.id:-16s}  (${count:3d})  ${c.name}'
	}
	return ok_result(cmd, lines.join('\n'), {
		'count':      summaries.len.str()
		'categories': json2.encode(summaries, escape_unicode: true)
	})
}

pub fn store_collections_result() CommandResult {
	cmd := 'store collections'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	mut summaries := []StoreCollectionSummary{}
	mut lines := []string{}
	for c in cat.collections {
		preview := if c.apps.len > 5 { c.apps[..5] } else { c.apps.clone() }
		summaries << StoreCollectionSummary{
			id:           c.id
			name:         c.name
			name_es:      c.name_es
			description:  c.description
			icon:         c.icon
			count:        c.apps.len
			preview_apps: preview
		}
		lines << '${c.id:-26s}  (${c.apps.len:2d})  ${c.name} — ${preview.join(', ')}'
	}
	return ok_result(cmd, lines.join('\n'), {
		'count':       summaries.len.str()
		'collections': json2.encode(summaries, escape_unicode: true)
	})
}

pub fn store_profiles_result() CommandResult {
	cmd := 'store profiles'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	snap := detect_installed_snapshot()
	mut summaries := []StoreProfileSummary{}
	mut lines := []string{}
	for p in cat.profiles {
		mut installed_cnt := 0
		mut all_ids := p.apps.clone()
		all_ids << p.proprietary_opt_in
		for aid in all_ids {
			if app := find_catalog_app(cat, aid) {
				inst, _ := app_install_status(app, snap)
				if inst {
					installed_cnt++
				}
			}
		}
		summaries << StoreProfileSummary{
			id:                       p.id
			name:                     p.name
			name_es:                  p.name_es
			description:              p.description
			app_count:                p.apps.len
			proprietary_opt_in_count: p.proprietary_opt_in.len
			installed_count:          installed_cnt
		}
		lines << '${p.id:-24s}  apps=${p.apps.len:2d}  opt-in=${p.proprietary_opt_in.len:2d}  installed=${installed_cnt:2d}  ${p.name}'
	}
	return ok_result(cmd, lines.join('\n'), {
		'count':    summaries.len.str()
		'profiles': json2.encode(summaries, escape_unicode: true)
	})
}

pub fn store_profile_show_result(id string) CommandResult {
	cmd := 'store profile-show'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	mut found := StoreProfile{}
	mut ok := false
	for p in cat.profiles {
		if p.id == id {
			found = p
			ok = true
			break
		}
	}
	if !ok {
		return fail_result(cmd, 'unknown store profile: ${id}')
	}
	snap := detect_installed_snapshot()
	pol := load_store_policy()
	mut oss_views := []StoreAppView{}
	mut prop_views := []StoreAppView{}
	mut installed_count := 0
	for aid in found.apps {
		if a := find_catalog_app(cat, aid) {
			v := build_app_view(a, snap, pol)
			if v.installed {
				installed_count++
			}
			oss_views << v
		}
	}
	for aid in found.proprietary_opt_in {
		if a := find_catalog_app(cat, aid) {
			v := build_app_view(a, snap, pol)
			if v.installed {
				installed_count++
			}
			prop_views << v
		}
	}
	total := oss_views.len + prop_views.len
	detail := {
		'id':               json2.Any(found.id)
		'name':             json2.Any(found.name)
		'name_es':          json2.Any(found.name_es)
		'description':      json2.Any(found.description)
		'description_es':   json2.Any(found.description_es)
		'apps':             json2.decode[json2.Any](json2.encode(oss_views, escape_unicode: true)) or {
			json2.Any('')
		}
		'proprietaryOptIn': json2.decode[json2.Any](json2.encode(prop_views, escape_unicode: true)) or {
			json2.Any('')
		}
	}
	mut lines := ['${found.name} (${found.id}) — ${installed_count}/${total} installed']
	lines << '  Open-source apps (${oss_views.len}): ${found.apps.join(', ')}'
	lines << '  Proprietary opt-in (${prop_views.len}): ${found.proprietary_opt_in.join(', ')}'
	return ok_result(cmd, lines.join('\n'), {
		'id':              found.id
		'installed_count': installed_count.str()
		'total_count':     total.str()
		'profile':         json2.encode(detail, escape_unicode: true)
	})
}

pub fn store_installed_result(backend_filter string) CommandResult {
	cmd := 'store installed'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	snap := detect_installed_snapshot()
	pol := load_store_policy()

	mut catalog_matches := []StoreAppView{}
	mut matched_pacman := []string{}
	mut matched_flatpak := []string{}
	mut matched_appimage := []string{}
	mut matched_webapp := []string{}

	for a in cat.apps {
		inst, via := app_install_status(a, snap)
		if !inst {
			continue
		}
		if backend_filter.len > 0 && via != backend_filter {
			continue
		}
		catalog_matches << build_app_view(a, snap, pol)
		for s in a.sources {
			match s.backend {
				'arch_native', 'vendor_repo', 'aur' { matched_pacman << s.package_id }
				'flatpak' { matched_flatpak << s.package_id }
				'appimage' { matched_appimage << a.id }
				'webapp' { matched_webapp << a.id }
				else {}
			}
		}
	}

	mut external := []map[string]string{}
	if backend_filter.len == 0 || backend_filter == 'arch_native' {
		for p in snap.pacman_pkgs {
			if p !in matched_pacman {
				external << {
					'backend': 'arch_native'
					'id':      p
				}
			}
		}
	}
	if backend_filter.len == 0 || backend_filter == 'flatpak' {
		for f in snap.flatpak_ids {
			if f !in matched_flatpak {
				external << {
					'backend': 'flatpak'
					'id':      f
				}
			}
		}
	}
	if backend_filter.len == 0 || backend_filter == 'appimage' {
		for ai in snap.appimages {
			if ai.id !in matched_appimage {
				external << {
					'backend': 'appimage'
					'id':      ai.id
				}
			}
		}
	}
	if backend_filter.len == 0 || backend_filter == 'webapp' {
		for wa in snap.webapps {
			if wa.id !in matched_webapp {
				external << {
					'backend': 'webapp'
					'id':      wa.id
				}
			}
		}
	}

	mut lines := ['Installed catalog apps (${catalog_matches.len}):']
	for v in catalog_matches {
		lines << '  ${v.id:-26s}  [${v.installed_via}]  ${v.name}'
	}
	lines << 'External non-catalog packages/apps: ${external.len}'
	return ok_result(cmd, lines.join('\n'), {
		'count':          catalog_matches.len.str()
		'external_count': external.len.str()
		'apps':           json2.encode(catalog_matches, escape_unicode: true)
		'external_apps':  json2.encode(external, escape_unicode: true)
	})
}

fn store_guided_install_result(cmd string, app StoreApp, src StoreSource, dry_run bool) CommandResult {
	mut guidance := ''
	if app.id == 'hermes-agent' {
		guidance = 'Hornero Javi/Hermes Assistant is managed natively via `horneroctl assistant setup --dry-run` (then `--yes`).'
	} else if src.backend == 'vendor_repo' {
		guidance = 'Vendor-signed repository (${src.remote}) required for `${src.package_id}`. Review vendor documentation at ${app.homepage} and GPG fingerprint before enabling the pacman repository; HorneroOS never pipes curl directly to shell.'
	} else {
		guidance = 'Guided upstream install for `${app.name}` (`${src.package_id}`): ${src.recommended_reason} Docs: ${app.support_url}. HorneroOS never pipes curl to shell blindly.'
	}
	if !dry_run {
		record_store_audit('install-guided', app.id, src.backend, true, src.package_id)
	}
	return ok_result(cmd, guidance, {
		'id':           app.id
		'backend':      src.backend
		'package_id':   src.package_id
		'guided':       'true'
		'dry_run':      dry_run.str()
		'homepage':     app.homepage
		'support_url':  app.support_url
		'command_line': guidance
	})
}

pub fn store_install_result(opts StoreInstallOptions) CommandResult {
	cmd := 'store install'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	app := find_catalog_app(cat, opts.id) or {
		return fail_result(cmd, 'application not found in catalog: ${opts.id}')
	}
	src := select_source(app, opts.source) or { return fail_result(cmd, err.msg()) }
	pol := load_store_policy()
	allowed, reason := evaluate_store_policy(app, src, pol, opts.accept_proprietary, opts.allow_aur)
	if !allowed {
		return fail_result_data(cmd, 'blocked by policy: ${reason}', {
			'id':             app.id
			'backend':        src.backend
			'policy_blocked': 'true'
			'policy_reason':  reason
		})
	}
	if !opts.yes && !opts.dry_run {
		return fail_result(cmd, 'refusing to install "${app.id}" without --yes (preview with --dry-run).\nExample: horneroctl store install ${app.id} --dry-run')
	}

	if src.backend == 'guided' || src.backend == 'vendor_repo' {
		return store_guided_install_result(cmd, app, src, opts.dry_run)
	}

	if src.backend == 'webapp' {
		if opts.dry_run {
			return ok_result(cmd, 'Dry run: would register WebApp "${app.name}" (${src.package_id}).',
				{
					'dry_run':    'true'
					'id':         app.id
					'backend':    'webapp'
					'package_id': src.package_id
				})
		}
		entry := webapp_add(WebAppSpec{
			id:   app.id
			name: app.name
			url:  src.package_id
			icon: app.icon
		}) or {
			record_store_audit('install', app.id, 'webapp', false, err.msg())
			return fail_result(cmd, err.msg())
		}
		record_store_audit('install', app.id, 'webapp', true, entry.file_path)
		return ok_result(cmd, 'Installed WebApp "${app.name}" -> ${entry.file_path}', {
			'id':        app.id
			'backend':   'webapp'
			'file_path': entry.file_path
			'wm_class':  entry.wm_class
		})
	}

	if src.backend == 'flatpak' {
		fp := resolve_flatpak_bin()
		if fp.len == 0 && !opts.dry_run {
			return fail_result(cmd, 'flatpak binary not found; install flatpak first')
		}
		scope := if opts.scope == 'system' { 'system' } else { 'user' }
		mut prog := if fp.len > 0 { fp } else { 'flatpak' }
		mut args := ['install', '--${scope}', '-y', 'flathub', src.package_id]
		if scope == 'system' {
			pkexec := pkexec_or_fail('store install', opts.dry_run) or {
				return fail_result(cmd, err.msg())
			}
			args = [prog, 'install', '--system', '-y', 'flathub', src.package_id]
			prog = pkexec
		}
		rep := run_exec(ExecSpec{
			prog:        prog
			args:        args
			dry_run:     opts.dry_run
			timeout_sec: 300
		})
		if opts.dry_run {
			return ok_result(cmd, 'Dry run: would run ${rep.command_line}', {
				'dry_run':      'true'
				'id':           app.id
				'backend':      'flatpak'
				'package_id':   src.package_id
				'command_line': rep.command_line
			})
		}
		record_store_audit('install', app.id, 'flatpak', rep.ok, rep.command_line)
		if !rep.ok {
			return fail_result(cmd, 'flatpak install failed (exit ${rep.exit_code}): ${rep.output}')
		}
		return ok_result(cmd, 'Installed ${app.name} (${src.package_id}) via Flatpak (${scope}).', {
			'id':           app.id
			'backend':      'flatpak'
			'package_id':   src.package_id
			'command_line': rep.command_line
		})
	}

	if src.backend == 'arch_native' {
		lock_path := resolve_pacman_lock_path()
		if !opts.dry_run && os.exists(lock_path) {
			return fail_result(cmd, 'pacman database is locked (${lock_path} exists); wait for the active transaction to finish and never delete the lock')
		}
		pkexec := pkexec_or_fail('store install', opts.dry_run) or {
			return fail_result(cmd, err.msg())
		}
		pacman := pacman_or_fail('store install', opts.dry_run) or {
			return fail_result(cmd, err.msg())
		}
		rep := run_exec(ExecSpec{
			prog:        pkexec
			args:        [pacman, '-S', '--needed', '--noconfirm', src.package_id]
			dry_run:     opts.dry_run
			timeout_sec: 300
		})
		if opts.dry_run {
			return ok_result(cmd, 'Dry run: would run ${rep.command_line}', {
				'dry_run':      'true'
				'id':           app.id
				'backend':      'arch_native'
				'package_id':   src.package_id
				'command_line': rep.command_line
			})
		}
		record_store_audit('install', app.id, 'arch_native', rep.ok, rep.command_line)
		if !rep.ok {
			return fail_result(cmd, 'pacman install failed (exit ${rep.exit_code}): ${rep.output}')
		}
		return ok_result(cmd, 'Installed ${app.name} (${src.package_id}) via pacman.', {
			'id':           app.id
			'backend':      'arch_native'
			'package_id':   src.package_id
			'command_line': rep.command_line
		})
	}

	if src.backend == 'aur' {
		if os.geteuid() == 0 {
			return fail_result(cmd, 'refusing to run AUR helper as root; run as your normal user')
		}
		helper := resolve_aur_helper_bin()
		if helper.len == 0 {
			return fail_result(cmd, 'no AUR helper (yay/paru) found; inspect PKGBUILD at https://aur.archlinux.org/packages/${src.package_id} and build manually with makepkg')
		}
		rep := run_exec(ExecSpec{
			prog:        helper
			args:        ['-S', '--needed', '--noconfirm', src.package_id]
			dry_run:     opts.dry_run
			timeout_sec: 600
		})
		if opts.dry_run {
			return ok_result(cmd, 'Dry run: would run ${rep.command_line} (as non-root user)', {
				'dry_run':      'true'
				'id':           app.id
				'backend':      'aur'
				'package_id':   src.package_id
				'command_line': rep.command_line
			})
		}
		record_store_audit('install', app.id, 'aur', rep.ok, rep.command_line)
		if !rep.ok {
			return fail_result(cmd, 'AUR install failed (exit ${rep.exit_code}): ${rep.output}')
		}
		return ok_result(cmd, 'Installed ${app.name} (${src.package_id}) from AUR.', {
			'id':           app.id
			'backend':      'aur'
			'package_id':   src.package_id
			'command_line': rep.command_line
		})
	}

	if src.backend == 'appimage' {
		return store_appimage_install(app.id, app.name, src.package_id, app.icon, '', opts.dry_run,
			opts.yes)
	}

	return fail_result(cmd, 'backend "${src.backend}" is not installable directly')
}

pub fn store_webapp_list_result() CommandResult {
	items := webapp_list()
	mut lines := []string{}
	for item in items {
		lines << '${item.id}\t${item.name}\t${item.wm_class}${if item.profile_dir.len > 0 {
			'\tprofile=' + item.profile_dir
		} else {
			''
		}}'
	}
	if items.len == 0 {
		lines << 'No Hornero-managed WebApps installed.'
	}
	return ok_result('store webapp list', lines.join('\n'), {
		'count':   items.len.str()
		'webapps': json2.encode(items, escape_unicode: true)
	})
}

pub fn store_webapp_add_result(spec WebAppSpec, dry_run bool, yes bool) CommandResult {
	cmd := 'store webapp add'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to create WebApp without --yes (preview with --dry-run).\nExample: horneroctl store webapp add github --name GitHub --url https://github.com --dry-run')
	}
	if dry_run {
		safe_id := validate_app_id(spec.id) or { return fail_result(cmd, err.msg()) }
		return ok_result(cmd, 'Dry run: would create WebApp "${spec.name}" (${spec.url}) for id "${safe_id}".',
			{
				'dry_run':     'true'
				'id':          safe_id
				'url':         spec.url
				'profile_dir': spec.profile_dir
			})
	}
	entry := webapp_add(spec) or { return fail_result(cmd, err.msg()) }
	record_store_audit('webapp-add', entry.id, 'webapp', true, entry.file_path)
	return ok_result(cmd, 'Created WebApp ${entry.file_path}', {
		'id':          entry.id
		'file_path':   entry.file_path
		'wm_class':    entry.wm_class
		'profile_dir': entry.profile_dir
	})
}

pub fn store_webapp_remove_result(id string, dry_run bool, yes bool) CommandResult {
	cmd := 'store webapp remove'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to remove WebApp without --yes (preview with --dry-run).\nExample: horneroctl store webapp remove ${id} --dry-run')
	}
	if dry_run {
		safe_id := validate_app_id(id) or { return fail_result(cmd, err.msg()) }
		return ok_result(cmd, 'Dry run: would remove WebApp "${safe_id}" (user browser profiles preserved).',
			{
				'dry_run': 'true'
				'id':      safe_id
			})
	}
	removed := webapp_remove(id) or { return fail_result(cmd, err.msg()) }
	record_store_audit('webapp-remove', id, 'webapp', true, removed)
	return ok_result(cmd, 'Removed WebApp ${removed}', {
		'id':        id
		'file_path': removed
	})
}

pub fn store_remove_result(opts StoreRemoveOptions) CommandResult {
	cmd := 'store remove'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	app := find_catalog_app(cat, opts.id) or {
		return fail_result(cmd, 'application not found in catalog: ${opts.id}')
	}
	snap := detect_installed_snapshot()
	_, detected_via := app_install_status(app, snap)
	target_backend := if opts.source.len > 0 {
		opts.source
	} else if detected_via.len > 0 {
		detected_via
	} else {
		app.recommended_source
	}
	src := select_source(app, target_backend) or { return fail_result(cmd, err.msg()) }
	if !opts.yes && !opts.dry_run {
		return fail_result(cmd, 'refusing to remove "${app.id}" without --yes (preview with --dry-run).\nExample: horneroctl store remove ${app.id} --dry-run')
	}

	if src.backend == 'webapp' {
		if opts.dry_run {
			return ok_result(cmd, 'Dry run: would remove WebApp "${app.id}" (user browser profiles preserved).',
				{
					'dry_run': 'true'
					'id':      app.id
					'backend': 'webapp'
				})
		}
		removed := webapp_remove(app.id) or {
			record_store_audit('remove', app.id, 'webapp', false, err.msg())
			return fail_result(cmd, err.msg())
		}
		record_store_audit('remove', app.id, 'webapp', true, removed)
		return ok_result(cmd, 'Removed WebApp ${removed} (user config preserved).', {
			'id':        app.id
			'backend':   'webapp'
			'file_path': removed
		})
	}

	if src.backend == 'appimage' {
		return store_appimage_remove_result(app.id, opts.dry_run, opts.yes)
	}

	if src.backend == 'flatpak' {
		fp := resolve_flatpak_bin()
		if fp.len == 0 && !opts.dry_run {
			return fail_result(cmd, 'flatpak binary not found')
		}
		rep := run_exec(ExecSpec{
			prog:        if fp.len > 0 { fp } else { 'flatpak' }
			args:        ['uninstall', '-y', src.package_id]
			dry_run:     opts.dry_run
			timeout_sec: 120
		})
		if opts.dry_run {
			return ok_result(cmd, 'Dry run: would run ${rep.command_line} (user data preserved).',
				{
					'dry_run':      'true'
					'id':           app.id
					'backend':      'flatpak'
					'package_id':   src.package_id
					'command_line': rep.command_line
				})
		}
		record_store_audit('remove', app.id, 'flatpak', rep.ok, rep.command_line)
		if !rep.ok {
			return fail_result(cmd, 'flatpak uninstall failed: ${rep.output}')
		}
		return ok_result(cmd, 'Removed ${app.name} (${src.package_id}) via Flatpak (user data preserved).', {
			'id':           app.id
			'backend':      'flatpak'
			'package_id':   src.package_id
			'command_line': rep.command_line
		})
	}

	if src.backend in ['arch_native', 'vendor_repo', 'aur'] {
		lock_path := resolve_pacman_lock_path()
		if !opts.dry_run && os.exists(lock_path) {
			return fail_result(cmd, 'pacman database is locked (${lock_path} exists)')
		}
		pkexec := pkexec_or_fail('store remove', opts.dry_run) or {
			return fail_result(cmd, err.msg())
		}
		pacman := pacman_or_fail('store remove', opts.dry_run) or {
			return fail_result(cmd, err.msg())
		}
		rep := run_exec(ExecSpec{
			prog:        pkexec
			args:        [pacman, '-R', '--noconfirm', src.package_id]
			dry_run:     opts.dry_run
			timeout_sec: 120
		})
		if opts.dry_run {
			return ok_result(cmd, 'Dry run: would run ${rep.command_line} (user config preserved).',
				{
					'dry_run':      'true'
					'id':           app.id
					'backend':      src.backend
					'package_id':   src.package_id
					'command_line': rep.command_line
				})
		}
		record_store_audit('remove', app.id, src.backend, rep.ok, rep.command_line)
		if !rep.ok {
			return fail_result(cmd, 'pacman remove failed: ${rep.output}')
		}
		return ok_result(cmd, 'Removed ${app.name} (${src.package_id}) (user config preserved).', {
			'id':           app.id
			'backend':      src.backend
			'package_id':   src.package_id
			'command_line': rep.command_line
		})
	}

	return fail_result(cmd, 'cannot automatically remove guided app "${app.id}"')
}

pub fn store_update_result(opts StoreUpdateOptions) CommandResult {
	cmd := 'store update'
	if !opts.yes && !opts.dry_run {
		return fail_result(cmd, 'refusing to update packages without --yes (preview with --dry-run).\nExample: horneroctl store update --all --dry-run')
	}
	mut commands := []string{}
	// Update Flatpak (per-app or all)
	if opts.backend.len == 0 || opts.backend == 'flatpak' {
		mut fp_args := ['update', '-y']
		if opts.id.len > 0 {
			cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
			app := find_catalog_app(cat, opts.id) or {
				return fail_result(cmd, 'application not found in catalog: ${opts.id}')
			}
			src := select_source(app, 'flatpak') or { return fail_result(cmd, err.msg()) }
			fp_args << src.package_id
		}
		fp := resolve_flatpak_bin()
		if fp.len > 0 || opts.dry_run || opts.backend == 'flatpak' {
			prog := if fp.len > 0 { fp } else { 'flatpak' }
			rep := run_exec(ExecSpec{
				prog:        prog
				args:        fp_args
				dry_run:     opts.dry_run
				timeout_sec: 300
			})
			commands << rep.command_line
			if !opts.dry_run {
				record_store_audit('update', opts.id, 'flatpak', rep.ok, rep.command_line)
				if !rep.ok {
					return fail_result(cmd, 'flatpak update failed: ${rep.output}')
				}
			}
		}
	}
	// Native system update (NEVER partial upgrade; always full `pkexec pacman -Syu`)
	if (opts.all || opts.backend == 'arch_native') && opts.backend != 'flatpak' {
		lock_path := resolve_pacman_lock_path()
		if !opts.dry_run && os.exists(lock_path) {
			return fail_result(cmd, 'pacman database is locked (${lock_path} exists)')
		}
		pkexec := pkexec_or_fail('store update', opts.dry_run) or {
			return fail_result(cmd, err.msg())
		}
		pacman := pacman_or_fail('store update', opts.dry_run) or {
			return fail_result(cmd, err.msg())
		}
		rep := run_exec(ExecSpec{
			prog:        pkexec
			args:        [pacman, '-Syu', '--noconfirm']
			dry_run:     opts.dry_run
			timeout_sec: 600
		})
		commands << rep.command_line
		if !opts.dry_run {
			record_store_audit('update', '', 'arch_native', rep.ok, rep.command_line)
			if !rep.ok {
				return fail_result(cmd, 'pacman system update failed: ${rep.output}')
			}
		}
	}
	if opts.dry_run {
		return ok_result(cmd, 'Dry run: would run ${commands.join('; ')}', {
			'dry_run':      'true'
			'command_line': commands.join('; ')
		})
	}
	return ok_result(cmd, 'Completed update (${commands.join('; ')}).', {
		'command_line': commands.join('; ')
	})
}

pub fn store_launch_result(id string, dry_run bool) CommandResult {
	cmd := 'store launch'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	app := find_catalog_app(cat, id) or {
		return fail_result(cmd, 'application not found in catalog: ${id}')
	}
	snap := detect_installed_snapshot()
	installed, via := app_install_status(app, snap)
	if !installed && !dry_run {
		return fail_result(cmd, '"${app.id}" does not appear to be installed')
	}
	effective_via := if via.len > 0 { via } else { app.recommended_source }
	mut prog := ''
	mut args := []string{}
	match effective_via {
		'flatpak' {
			src := select_source(app, 'flatpak') or { return fail_result(cmd, err.msg()) }
			fp := resolve_flatpak_bin()
			prog = if fp.len > 0 { fp } else { 'flatpak' }
			args = ['run', src.package_id]
		}
		'webapp' {
			gl := resolve_gtk_launch_bin()
			prog = if gl.len > 0 { gl } else { 'gtk-launch' }
			args = ['hornero-webapp-${app.id}']
		}
		'appimage' {
			prog = os.join_path(resolve_store_appimages_dir(), '${app.id}.AppImage')
		}
		else {
			gl := resolve_gtk_launch_bin()
			src := select_source(app, effective_via) or { return fail_result(cmd, err.msg()) }
			if gl.len > 0 || dry_run {
				prog = if gl.len > 0 { gl } else { 'gtk-launch' }
				args = [src.package_id]
			} else {
				prog = src.package_id
			}
		}
	}
	line := command_line(prog, args)
	if dry_run {
		return ok_result(cmd, 'Dry run: would launch ${line}', {
			'dry_run':      'true'
			'id':           app.id
			'backend':      effective_via
			'command_line': line
		})
	}
	mut proc := os.new_process(prog)
	proc.set_args(args)
	proc.run()
	return ok_result(cmd, 'Launched ${app.name} (${line}).', {
		'id':           app.id
		'backend':      effective_via
		'command_line': line
	})
}

pub fn store_manifest_export_result(file string, dry_run bool, yes bool) CommandResult {
	cmd := 'store manifest export'
	if file.trim_space().len == 0 {
		return fail_result(cmd, 'missing output manifest file path')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to write manifest without --yes (preview with --dry-run).\nExample: horneroctl store manifest export ./apps.json --dry-run')
	}
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	snap := detect_installed_snapshot()
	pol := load_store_policy()
	mut installed_ids := []string{}
	for a in cat.apps {
		inst, _ := app_install_status(a, snap)
		if inst {
			installed_ids << a.id
		}
	}
	doc := StoreManifestDoc{
		api_version: 'hornero.os/v1'
		kind:        'ApplicationManifest'
		schema:      1
		policy:      StorePolicyDisk{
			allowed_sources:    pol.allowed_sources
			verified_only:      pol.verified_only
			open_source_only:   pol.open_source_only
			aur_policy:         pol.aur_policy
			proprietary_policy: pol.proprietary_policy
		}
		apps:        installed_ids
	}
	encoded := json2.encode(doc, escape_unicode: true) + '\n'
	if dry_run {
		return ok_result(cmd, 'Dry run: would export ${installed_ids.len} app(s) to ${file}.', {
			'dry_run': 'true'
			'file':    file
			'count':   installed_ids.len.str()
		})
	}
	write_file_atomic(file, encoded) or { return fail_result(cmd, err.msg()) }
	return ok_result(cmd, 'Exported ${installed_ids.len} app(s) to ${file}.', {
		'file':  file
		'count': installed_ids.len.str()
	})
}

fn load_and_validate_manifest(file string, cat AppCatalog) !([]string, []string) {
	raw := os.read_file(file) or { return error('cannot read manifest ${file}: ${err.msg()}') }
	decoded := json2.decode[json2.Any](raw) or {
		return error('invalid manifest JSON: ${err.msg()}')
	}
	m := decoded.as_map()
	if j_str(m, 'apiVersion') != 'hornero.os/v1' || j_str(m, 'kind') != 'ApplicationManifest' {
		return error('manifest must have apiVersion=hornero.os/v1 and kind=ApplicationManifest')
	}
	ids := j_str_list(m, 'apps')
	mut valid := []string{}
	mut unknown := []string{}
	for id in ids {
		if _ := find_catalog_app(cat, id) {
			valid << id
		} else {
			unknown << id
		}
	}
	return valid, unknown
}

pub fn store_manifest_import_result(file string) CommandResult {
	cmd := 'store manifest import'
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	valid, unknown := load_and_validate_manifest(file, cat) or {
		return fail_result(cmd, err.msg())
	}
	if unknown.len > 0 {
		return fail_result(cmd, 'manifest contains unknown catalog ids: ${unknown.join(', ')}')
	}
	return ok_result(cmd, 'Validated manifest ${file}: ${valid.len} catalog app(s).', {
		'file':  file
		'count': valid.len.str()
		'apps':  json2.encode(valid, escape_unicode: true)
	})
}

pub fn store_manifest_apply_result(file string, accept_proprietary bool, allow_aur bool, dry_run bool, yes bool) CommandResult {
	cmd := 'store manifest apply'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to apply manifest without --yes (preview with --dry-run).\nExample: horneroctl store manifest apply ./apps.json --dry-run')
	}
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	valid, unknown := load_and_validate_manifest(file, cat) or {
		return fail_result(cmd, err.msg())
	}
	if unknown.len > 0 {
		return fail_result(cmd, 'manifest contains unknown catalog ids: ${unknown.join(', ')}')
	}
	snap := detect_installed_snapshot()
	mut already := []string{}
	mut planned := []string{}
	mut installed := []string{}
	mut blocked := []string{}
	for id in valid {
		app := find_catalog_app(cat, id) or { continue }
		is_inst, _ := app_install_status(app, snap)
		if is_inst {
			already << id
			continue
		}
		if dry_run {
			res := store_install_result(StoreInstallOptions{
				id:                 id
				accept_proprietary: accept_proprietary
				allow_aur:          allow_aur
				dry_run:            true
			})
			if res.ok {
				planned << id
			} else {
				blocked << '${id}: ${res.message}'
			}
		} else {
			res := store_install_result(StoreInstallOptions{
				id:                 id
				accept_proprietary: accept_proprietary
				allow_aur:          allow_aur
				yes:                true
			})
			if res.ok {
				installed << id
			} else {
				blocked << '${id}: ${res.message}'
			}
		}
	}
	data := {
		'file':      file
		'dry_run':   dry_run.str()
		'already':   json2.encode(already, escape_unicode: true)
		'planned':   json2.encode(planned, escape_unicode: true)
		'installed': json2.encode(installed, escape_unicode: true)
		'blocked':   json2.encode(blocked, escape_unicode: true)
	}
	if blocked.len > 0 {
		return fail_result_data(cmd, 'manifest apply had blocked/failed items: ${blocked.join('; ')}', data)
	}
	msg := if dry_run {
		'Dry run: ${already.len} already installed, ${planned.len} planned to install.'
	} else {
		'Applied manifest: ${already.len} already installed, ${installed.len} installed.'
	}
	return ok_result(cmd, msg, data)
}

fn load_store_queue() StoreQueueDoc {
	path := resolve_store_queue_file()
	if !os.is_file(path) {
		return StoreQueueDoc{}
	}
	raw := os.read_file(path) or { return StoreQueueDoc{} }
	return json2.decode[StoreQueueDoc](raw) or { StoreQueueDoc{} }
}

fn save_store_queue(q StoreQueueDoc) !string {
	path := resolve_store_queue_file()
	write_file_atomic(path, json2.encode(q, escape_unicode: true) + '\n')!
	return path
}

pub fn store_queue_list_result() CommandResult {
	q := load_store_queue()
	mut lines := []string{}
	for item in q.items {
		lines << '${item.id}\t(${if item.backend.len > 0 { item.backend } else { 'recommended' }})'
	}
	if q.items.len == 0 {
		lines << 'Onboarding queue is empty.'
	}
	return ok_result('store queue list', lines.join('\n'), {
		'path':  resolve_store_queue_file()
		'count': q.items.len.str()
		'items': json2.encode(q.items, escape_unicode: true)
	})
}

pub fn store_queue_add_result(id string, backend string, dry_run bool, yes bool) CommandResult {
	cmd := 'store queue add'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to modify queue without --yes (preview with --dry-run)')
	}
	cat := load_app_catalog() or { return fail_result(cmd, err.msg()) }
	app := find_catalog_app(cat, id) or {
		return fail_result(cmd, 'application not found in catalog: ${id}')
	}
	if backend.len > 0 {
		_ = select_source(app, backend) or { return fail_result(cmd, err.msg()) }
	}
	mut q := load_store_queue()
	if !q.items.any(it.id == app.id) {
		q.items << StoreQueueItem{
			id:      app.id
			backend: backend
		}
	}
	if dry_run {
		return ok_result(cmd, 'Dry run: would queue "${app.id}" (${q.items.len} item(s) total).', {
			'dry_run': 'true'
			'id':      app.id
			'count':   q.items.len.str()
		})
	}
	path := save_store_queue(q) or { return fail_result(cmd, err.msg()) }
	return ok_result(cmd, 'Queued "${app.id}" in ${path}.', {
		'id':    app.id
		'path':  path
		'count': q.items.len.str()
	})
}

pub fn store_queue_remove_result(id string, dry_run bool, yes bool) CommandResult {
	cmd := 'store queue remove'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to modify queue without --yes (preview with --dry-run)')
	}
	mut q := load_store_queue()
	before := q.items.len
	q.items = q.items.filter(it.id != id)
	if q.items.len == before {
		return fail_result(cmd, '"${id}" is not in the store queue')
	}
	if dry_run {
		return ok_result(cmd, 'Dry run: would remove "${id}" from queue.', {
			'dry_run': 'true'
			'id':      id
			'count':   q.items.len.str()
		})
	}
	path := save_store_queue(q) or { return fail_result(cmd, err.msg()) }
	return ok_result(cmd, 'Removed "${id}" from ${path}.', {
		'id':    id
		'path':  path
		'count': q.items.len.str()
	})
}

pub fn store_queue_clear_result(dry_run bool, yes bool) CommandResult {
	cmd := 'store queue clear'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to clear queue without --yes (preview with --dry-run)')
	}
	if dry_run {
		return ok_result(cmd, 'Dry run: would clear store queue.', {
			'dry_run': 'true'
			'count':   '0'
		})
	}
	path := save_store_queue(StoreQueueDoc{}) or { return fail_result(cmd, err.msg()) }
	return ok_result(cmd, 'Cleared store queue at ${path}.', {
		'path':  path
		'count': '0'
	})
}

pub fn store_queue_run_result(accept_proprietary bool, allow_aur bool, dry_run bool, yes bool) CommandResult {
	cmd := 'store queue run'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to run queue without --yes (preview with --dry-run)')
	}
	q := load_store_queue()
	mut succeeded := []string{}
	mut failed := []string{}
	mut remaining := []StoreQueueItem{}
	for item in q.items {
		res := store_install_result(StoreInstallOptions{
			id:                 item.id
			source:             item.backend
			accept_proprietary: accept_proprietary
			allow_aur:          allow_aur
			dry_run:            dry_run
			yes:                yes
		})
		if res.ok {
			succeeded << item.id
		} else {
			failed << '${item.id}: ${res.message}'
			remaining << item
		}
	}
	if !dry_run {
		save_store_queue(StoreQueueDoc{
			items: remaining
		}) or {}
	}
	data := {
		'dry_run':   dry_run.str()
		'succeeded': json2.encode(succeeded, escape_unicode: true)
		'failed':    json2.encode(failed, escape_unicode: true)
		'remaining': remaining.len.str()
	}
	if failed.len > 0 {
		return fail_result_data(cmd, 'queue run failed for: ${failed.join('; ')}', data)
	}
	return ok_result(cmd, '${if dry_run { 'Dry run: would process' } else { 'Processed' }} ${succeeded.len} queued app(s).',
		data)
}

pub fn store_gui_result(app_id string, dry_run bool) CommandResult {
	cmd := 'store gui'
	mut args := ['-c', 'hornero', 'ipc', 'call', 'apps', 'open']
	if app_id.trim_space().len > 0 {
		args << app_id.trim_space()
	}
	qs := resolve_store_qs_bin()
	if os.getenv('HORNERO_BYPASS_QUICKSHELL') == '1' || dry_run {
		line := command_line(if qs.len > 0 { qs } else { 'qs' }, args)
		return ok_result(cmd, 'Dry run: would invoke ${line}', {
			'dry_run':      'true'
			'command_line': line
		})
	}
	if qs.len == 0 {
		return fail_result(cmd, 'qs (Quickshell) binary not found on PATH')
	}
	rep := run_exec(ExecSpec{
		prog:        qs
		args:        args
		timeout_sec: 10
	})
	if !rep.ok {
		return fail_result(cmd, 'quickshell IPC failed: ${rep.output}')
	}
	return ok_result(cmd, 'Opened Hornero Apps.', {
		'command_line': rep.command_line
	})
}
