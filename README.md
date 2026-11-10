# hyprland-dotfiles

Ma session Hyprland (à côté de GNOME, choisie dans GDM) : Hyprland 0.53, Waybar, widgets Quickshell,
couleurs dynamiques Pywal (Catppuccin-like), fonds d'écran image/vidéo/diaporama.
Machine d'origine : Ubuntu 26.04, Ryzen 7 3700X, RTX 3070 (driver NVIDIA 580 open), écrans DP-1 2560×1440 165 Hz + DP-2 1920×1080 144 Hz.

## Contenu

| Dossier | Quoi |
|---|---|
| `home/.config/hypr` | `hyprland.conf` (raccourcis AZERTY, écrans, règles), `hypridle`, `hyprlock`, `xdph.conf` (sélecteur de partage d'écran) |
| `home/.config/waybar` | barre en pilules (apps, date, vitals, réglages) |
| `home/.config/quickshell/controls` | panneaux : son, calendrier, lecteur, alimentation et **tableau de bord** (Accueil, Météo, Actualités, Cyber, Agenda, GitHub, Mises à jour, Performances) |
| `home/.config/quickshell/clock` | horloge de bureau (style DesktopSuite « Mond Minimal ») |
| `home/.config/quickshell/overview` | vue d'ensemble Super+Tab (glisser-déposer, snapping) |
| `home/.config/quickshell/wallpicker` | sélecteur de fonds d'écran (Super+P) |
| `home/.config/quickshell/sharepicker` | sélecteur de partage d'écran façon GNOME |
| `home/.config/wal/templates` | templates Pywal → couleurs Hyprland, Dunst, Tofi, qt6ct |
| `home/.local/bin` | scripts : récupération des données des widgets (`*-fetch`, `sysstats`), fonds d'écran (`hypr-wallpaper`, `hypr-slideshow`), Waybar (`waybar-*`), Minecraft dev (`mc-*`), `sys-update`, `zen-open`… |
| `home/.local/share/applications` | lanceurs `.desktop` (Claude Code, Zen, Spotify en X11) |

Le chemin du home est stocké sous la forme `@HOME@` et remplacé à l'installation.

## Utilisation

```bash
# Sur une nouvelle machine (après les dépendances ci-dessous)
git clone git@github.com:Altaks/hyprland-dotfiles.git && cd hyprland-dotfiles
./install.sh          # sauvegarde tout fichier existant différent en *.bak-dotfiles

# Sur la machine d'origine, pour mettre le dépôt à jour
./sync.sh && git add -A && git commit -m "…" && git push
```

## Dépendances

### Paquets Ubuntu

```bash
sudo apt install hyprland hypridle hyprlock hyprpicker hyprpolkitagent xdg-desktop-portal-hyprland \
  waybar dunst tofi grim slurp wl-clipboard cliphist brightnessctl playerctl qt6ct jq imagemagick \
  python3-pil python3-venv pipx mpv libmpv-dev ptyxis nautilus gnome-keyring \
  qml6-module-qtlocation qt6-location-plugins \
  cmake ninja-build qt6-base-dev qt6-declarative-dev cargo rustc liblz4-dev
sudo locale-gen fr_FR.UTF-8      # dates en français dans la barre et les widgets
```

### Outils installés à la main (dans `~/.local`)

Ces étapes ont été faites à la main sur la machine d'origine ; elles n'ont pas été rejouées sur une machine vierge.

- **Quickshell 0.3.2** (widgets) : compiler depuis les sources avec
  `cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCRASH_HANDLER=OFF -DINSTALL_QML_PREFIX=lib/qt6/qml -DCMAKE_INSTALL_PREFIX=$HOME/.local`
  puis `cmake --build build && cmake --install build`. Lien `~/.local/bin/qs` → `quickshell`.
  Les dépendances de build exactes sont dans la doc de Quickshell (Qt 6 Wayland, ShaderTools, PipeWire…).
- **awww** (fonds d'écran animés) : `cargo build --release` depuis le dépôt awww, copier `awww` et `awww-daemon` dans `~/.local/bin`.
- **mpvpaper** (fonds d'écran vidéo) : build meson, binaires dans `~/.local/bin`.
- **hyprland-guiutils** (dialogues Hyprland) : build cmake, `pkexec cmake --install build` (va dans `/usr/local/bin`) ; à recompiler si hyprtoolkit change de version.
- **pywal16** : `pipx install pywal16`.
- **gh** (onglet GitHub) : `brew install gh` puis `gh auth login -s user` (le scope `user` sert à la facturation).
- **Zen Browser** : AppImage dans `~/Applications/` (mise à jour : `zen-update`).
- Python des widgets : `install.sh` crée `~/.local/share/dashboard-venv` (icalendar pour l'agenda, gtfs-realtime-bindings pour Naolib).

### Polices

- CaskaydiaCove Nerd Font (barre, widgets) et Montserrat (horloge) dans `~/.local/share/fonts`.
- Anurati (horloge) : licence usage personnel, à télécharger soi-même sur DaFont.

## Étapes manuelles après installation

C'est ma config personnelle, pas un installeur générique : plusieurs choses sont propres à ma machine et à Nantes.

- **Fonds d'écran** : à mettre dans `~/Pictures/backgrounds` (non inclus : poids et droits). Photo de profil de l'accueil : `~/.face` (le prénom affiché est `$USER`).
- **Naolib** : `naolib-fetch --find "arrêt"` puis `naolib-fetch --set "Arrêt 1" "Arrêt 2"` (arrêts suivis dans l'onglet Nantes). Le premier lancement télécharge le GTFS (~20 Mo) et le fond de carte OpenStreetMap.
- **Itinéraires** : clé API Google (Routes API activée) dans `~/.config/quickshell/google-maps.key` ; sans clé, la recherche ouvre Google Maps.
- **Agenda** : coller les adresses iCal secrètes de Google Agenda dans `~/.config/quickshell/agenda.json` (créé depuis `agenda.example.json`, jamais versionné).
- **Météo** : `weather-fetch --set "Ville"`.
- **Écrans** : adapter les lignes `monitor =` et les règles d'espaces de travail de `hyprland.conf` (DP-1/DP-2), ainsi que `hyprlock.conf` et l'horloge (`quickshell/clock/shell.qml`), qui visent DP-1.
- **Nantes** : les onglets Nantes (Naolib, carte, itinéraires), « Sortir à Nantes » et l'actualité locale utilisent des sources propres à Nantes ; ailleurs, ils restent vides ou sont à retirer de `quickshell/controls/shell.qml`.
- **Chemins d'applis** : `$minecraft` (AppImage Prism Launcher) dans `hyprland.conf` et Homebrew dans `/home/linuxbrew` (`sys-update`, `github-fetch`).
- **Veille cyber** : la liste `WATCH` de `cyber-fetch` (logiciels « qui te concernent ») est à adapter à ta machine.
- **NVIDIA** : les variables d'environnement NVIDIA en tête de `hyprland.conf` ne servent que sur carte NVIDIA.
- Ne pas laisser Zen se déclarer « navigateur par défaut » : il remplace `zen-open` et les liens repassent par AppImageLauncher.

## Raccourcis principaux

Super+T Ptyxis · Super+B Zen · Super+F Nautilus · Super+X Tofi · Super+D Discord · Super+C Claude Code · Super+S Spotify ·
Super+M Prism Launcher · Super+J JetBrains Toolbox · Super+Tab vue d'ensemble · Super+P fonds d'écran · Super+W fermer ·
Super+Ctrl+←/→ espace de travail · Super+Shift+←/→ déplacer la fenêtre · Super+Alt+←/→ autre écran · Alt+Tab fenêtres · Impr capture de zone.
