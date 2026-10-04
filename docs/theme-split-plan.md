# Theme data and runtime ownership

Hornero themes are installed data packs. HorneroOS/config owns pack metadata,
wallpaper manifests, semantic tokens, and generated catalogue indexes. The
Shell owns previews and live session presentation. `horneroctl` owns stable
catalogue resolution and coordinates theme application with the Shell and
operating-system settings.

## Pack concepts

The catalogue deliberately supports two useful levels of detail:

- **Semantic themes** define a versioned palette and component roles. The
  Hornero flagship themes use this richer contract for controlled contrast,
  GTK integration, and consistent Shell surfaces.
- **Appearance recipes** choose an existing scheme type, GTK/icon choices, and
  optional wallpaper media. They remain lightweight and do not claim a
  semantic token set they do not define.

Both are first-class catalogue items. `catalogue/registry.json` is generated
from the installed packs; it is not edited independently. Pack validation and
schema ownership live with HorneroOS/config.

## Resolution and media

The user catalogue overrides packaged system data intentionally. Writes always
stay in user-owned XDG locations. Wallpapers are referenced through manifests
and may remain optional; a missing image is represented as unavailable rather
than invalidating the theme pack. Hornero does not silently download theme or
wallpaper assets.

## Apply and preview

Appearance Settings owns temporary preview state. Theme application validates
the pack, applies Shell mode and palette, wallpaper policy, GTK theme and color
scheme, and icon theme through the shared apply path. `horneroctl` verifies
resulting state and returns an actionable failure when a required subsystem
cannot be updated. The UI uses the same catalogue and preview frame for
semantic themes and recipes.

## Change ownership

Schema changes start in HorneroOS/config, followed by the Shell consumer and
CLI validation where required. The website consumes reviewed product data and
certified media rather than maintaining a second theme registry. See
[`PATH_CONTRACT.md`](PATH_CONTRACT.md) and the config repository's theme-pack
validation for implementation details.
