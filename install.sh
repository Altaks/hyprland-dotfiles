#!/usr/bin/env bash
# Installe la config sur cette machine : copie home/ dans $HOME (@HOME@ → $HOME).
# Tout fichier existant et différent est d'abord sauvegardé en <fichier>.bak-dotfiles.
# Les dépendances (paquets, outils compilés) sont décrites dans le README.
set -euo pipefail
cd "$(dirname "$0")"
while read -r f; do
    [[ -z "$f" || "$f" == \#* ]] && continue
    src="home/$f" dst="$HOME/$f"
    [ -e "$src" ] || continue
    mkdir -p "$(dirname "$dst")"
    tmp="$(mktemp)"; sed "s#@HOME@#$HOME#g" "$src" > "$tmp"; chmod --reference="$src" "$tmp"
    if [ -e "$dst" ] && ! cmp -s "$tmp" "$dst"; then cp -a "$dst" "$dst.bak-dotfiles"; echo "sauvegardé : $dst.bak-dotfiles"; fi
    mv "$tmp" "$dst"
done < files.txt

# Agenda : modèle à compléter (jamais écrasé)
[ -e ~/.config/quickshell/agenda.json ] || { cp home/.config/quickshell/agenda.example.json ~/.config/quickshell/agenda.json; chmod 600 ~/.config/quickshell/agenda.json; }
# Dunst lit la config générée par pywal
mkdir -p ~/.config/dunst && ln -sfn ~/.cache/wal/dunstrc ~/.config/dunst/dunstrc
# Python des widgets (agenda : lecture iCal)
[ -x ~/.local/share/dashboard-venv/bin/python ] || {
    python3 -m venv ~/.local/share/dashboard-venv
    ~/.local/share/dashboard-venv/bin/pip install -q icalendar recurring-ical-events gtfs-realtime-bindings
}
# Liens web → Zen via zen-open (contourne AppImageLauncher)
for t in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml; do xdg-mime default zen-open.desktop "$t"; done
command -v gh >/dev/null && gh config set browser "setsid -f $HOME/.local/bin/zen-open"
echo "Terminé. Voir le README pour les dépendances et les étapes manuelles."
