# Hornero path contract

Hornero owns its settings, data, cache and state under the `hornero` XDG
namespace. The Shell, `horneroctl` and packaged configuration use these same
locations. User-owned catalogues take precedence over read-only system
catalogues. Writes always stay in user-owned paths; installed package data is
never modified at runtime.

## User and system locations

| Data | User location | System location |
| --- | --- | --- |
| Shell settings | `$XDG_CONFIG_HOME/hornero/shell.json` | `/etc/xdg/hornero/shell.json` |
| Theme packs | `$XDG_DATA_HOME/hornero/themes/` | `$XDG_DATA_DIRS/hornero/themes/` |
| Layout presets | `$XDG_DATA_HOME/hornero/shell-presets/` | `$XDG_DATA_DIRS/hornero/shell-presets/` |
| Wallpapers | `$XDG_DATA_HOME/hornero/wallpapers/` | `$XDG_DATA_DIRS/hornero/wallpapers/` |
| Current layout | `$XDG_STATE_HOME/hornero/current-shell-preset` | — |
| Current wallpaper | `$XDG_STATE_HOME/hornero/wallpaper/path` | — |
| Appearance state | `$XDG_STATE_HOME/hornero/scheme/state.json` | — |
| Generated palette | `$XDG_CACHE_HOME/hornero/smart-colors/scheme.json` | — |
| Notifications | `$XDG_STATE_HOME/hornero/notifs.json` | — |
| Image cache | `$XDG_CACHE_HOME/hornero/imagecache/` | — |
| Lock-screen effects | `$XDG_CACHE_HOME/hornero/lockscreen/` | — |
| Snapshots | `$XDG_DATA_HOME/hornero/snapshots/` | — |

When an XDG variable is unset, Hornero uses the standard locations under the
user's home directory. The Shell configuration package also installs
read-only runtime helpers under `/usr/share/hornero/lib/hornero/`.

## Catalogue resolution

For themes, presets and wallpaper media, Hornero searches the explicit
`HORNERO_*_DIR` override when one is supplied. Otherwise it checks the user
catalogue first and then system data directories in XDG order. A user item
with the same ID intentionally replaces the packaged item. An absent optional
wallpaper does not invalidate its theme; the interface reports that the media
is unavailable.

The theme registry is generated from the installed theme packs. It is not an
independent catalogue to edit by hand.

## Ownership

The Shell owns live session state and user settings. `horneroctl` owns stable
system operations and the shared file contracts. Hornero configuration
packages own defaults and read-only catalogue assets. Personal configuration
sources can provide user overrides, but system packages remain unchanged.

See [CLI architecture](cli-architecture.md),
[theme architecture](theme-split-plan.md), and
[configuration defaults](FACTORY_DEFAULTS.md) for the corresponding runtime
and package responsibilities.
