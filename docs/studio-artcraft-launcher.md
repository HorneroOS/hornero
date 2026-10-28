# ArtCraft Launcher (AppImage, manual) — Studio reference-only

Status: `reference-only`. No se instala desde el catálogo ni viaja en la ISO.
Modelo: como `penpot` en `editions/catalogue.yaml`.

## Por qué así y no AUR

El AUR `artcraft-launcher-appimage` es un wrapper finito del AppImage oficial
(bajar + `chmod +x` + `.desktop`). Añade un maintainer intermedio y no aporta
reproducibilidad frente a la descarga directa verificada. El build desde
fuente (`artcraft-launcher`, alerque) es auditable pero pesado (cargo/Rust)
para una Preview. Se documenta el flujo manual que ya usa el equipo.

Fuente: https://github.com/storytold/craft-launcher/releases
Versión probada: `0.8.1` (actualizar aquí cuando se revalide).

Verificado 2026-10-28 en CachyOS (base Arch, kernel con KVM):
AppImage x86_64 de 12 MB, `SHA256SUMS.txt` OK, ELF x86-64 type2-runtime
estático, `--help` arranca (log `ArtCraft Launcher 0.8.1`) y sale 0 sin
display. El montaje normal requiere FUSE funcional en el host (presente
acá); verificar que la ISO Preview lo traiga, si no usar
`APPIMAGE_EXTRACT_AND_RUN=1`.
GUI en Hyprland/Niri pendiente (requiere VM Hornero).
Smoke test real 2026-10-28 en PC del equipo (CachyOS/Arch, Hyprland 0.56.2,
Wayland, `xdg-desktop-portal` + `xdg-desktop-portal-hyprland` activos):
el AppImage abrió ventana nativa sin errores en el log. Valida
Arch+Hyprland+portal (base casi idéntica a Hornero Desktop), NO la
integración con Hornero Shell ni la ISO (eso sigue pidiendo VM Hornero).

Evidencia (en `/tmp/opencode/artcraft-verify/`):
- `shot1-launcher-evidence.png`: launcher 0.8.1, grilla con PhotoCraft
  instalado (OPEN) y resto disponible para instalar.
- `shot2-photocraft.png`: PhotoCraft lanzado desde el launcher en
  workspace 6, start screen + paneles OK. End-to-end launcher→app
  verificado en Arch+Hyprland.

## Instalación manual

```bash
mkdir -p ~/Applications && cd ~/Applications
ARCH=$(uname -m)  # x86_64 o aarch64, igual que los assets del release
curl -LO https://github.com/storytold/craft-launcher/releases/download/v0.8.1/artcraft-launcher-0.8.1-linux-${ARCH}.AppImage
curl -LO https://github.com/storytold/craft-launcher/releases/download/v0.8.1/SHA256SUMS.txt
grep "artcraft-launcher-0.8.1-linux-${ARCH}.AppImage$" SHA256SUMS.txt | sha256sum -c -
chmod +x artcraft-launcher-0.8.1-linux-${ARCH}.AppImage
./artcraft-launcher-0.8.1-linux-${ARCH}.AppImage
```
El `grep` limita la verificación al archivo descargado: si la entrada
falta o el nombre no coincide, falla en vez de pasar en silencio
(`--ignore-missing` ocultaría ese caso).

Prerequisitos Wayland/Hyprland (ya están en Desktop; si falta algo):
`wayland, xdg-desktop-portal[-hyprland], mesa/vulkan-icd-loader, noto-fonts-cjk`
(opcional CJK). El AppImage usa un runtime estático; para el montaje
normal se necesita FUSE funcional en el host, pero no `libfuse2`.
Si FUSE no está disponible, usar `APPIMAGE_EXTRACT_AND_RUN=1`.

Las Craft apps se instalan/actualizan desde el propio launcher, fuera de
pacman: la versión del catálogo solo vale al momento de la instalación.
No usar con apps en ejecución (el launcher lo bloquea).

## Cómo probarlo

1. Composición (sin VM):
   ```bash
   python3 scripts/resolve-edition.py studio --application artcraft-launcher
   # debe fallar con: reference-only and cannot be installed from the catalogue
   python3 -m pytest tests/test_studio_selection.py tests/test_editions.py tests/test_composition.py -q
   ```
2. Humo manual en VM HorneroOS Desktop/Studio Preview (Hyprland, luego Niri):
   - AppImage ejecuta, icono aparece en el launcher de Hornero Shell.
   - `desktop-file-validate` del `.desktop` generado si se integra a menú.
   - Abrir file-dialog (usa portal), crear un proyecto, instalar/actualizar
     una Craft app, tomar screenshot.
   - Repetir en Niri (experimental): solo reportar, no bloquea.
3. Evidencia: screenshots + `run.json`-style manual (ISO SHA, versión
   launcher, compositor). Sin bundle PASS no hay promoción a `support`.
   Ver `HorneroOS/qa:docs/STUDIO-ACCEPTANCE.md` (gate fail-closed).
