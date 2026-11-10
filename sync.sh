#!/usr/bin/env bash
# Recopie la config de cette machine dans le dépôt (à lancer avant un commit).
# Le chemin du home d'origine est remplacé par @HOME@ ; install.sh fait l'inverse.
set -euo pipefail
cd "$(dirname "$0")"
while read -r f; do
    [[ -z "$f" || "$f" == \#* ]] && continue
    [ -e "$HOME/$f" ] || { echo "absent : $f" >&2; continue; }
    mkdir -p "home/$(dirname "$f")"
    sed "s#$HOME#@HOME@#g" "$HOME/$f" > "home/$f"
    chmod --reference="$HOME/$f" "home/$f"
done < files.txt
# Parties personnelles qui restent en local : environnement de dev Minecraft,
# prénom et photo de l'accueil (remplacés par $USER et ~/.face dans le dépôt)
python3 - home/.config/waybar/config.jsonc home/.config/waybar/style.css <<'PY'
import re, sys
cfg, css = sys.argv[1], sys.argv[2]
s = open(cfg).read()
s = s.replace('"group/mcdev", ', '')
s = re.sub(r'\n[ \t]*// Environnement de dev Minecraft[^\n]*(?=\n[ \t]*"group/mcdev")', '', s)
s = re.sub(r'\n[ \t]*"(group/mcdev|custom/mcdev(-close)?)": \{.*?\n[ \t]*\},', '', s, flags=re.S)
open(cfg, 'w').write(s)
s = open(css).read()
s = s.replace('#custom-claude:hover,\n#custom-mcdev:hover,\n#custom-mcdev-close:hover {', '#custom-claude:hover {')
s = re.sub(r'^#(custom-)?mcdev(-close)?,\n', '', s, flags=re.M)
s = re.sub(r'\n#custom-mcdev(-close)? \{.*?\n\}\n', '', s, flags=re.S)
open(css, 'w').write(s)
qml = 'home/.config/quickshell/controls/shell.qml'
s = open(qml).read()
s = s.replace('"/Pictures/pfp/altaks.png"', '"/.face"').replace('+ ", Altaks"', '+ ", " + Quickshell.env("USER")')
open(qml, 'w').write(s)
PY
# Agenda : uniquement le modèle (les adresses iCal sont secrètes)
mkdir -p home/.config/quickshell
cat > home/.config/quickshell/agenda.example.json <<'JSON'
{
  "calendars": [
    {"name": "Perso", "url": "https://calendar.google.com/calendar/ical/.../private-.../basic.ics", "color": "#8aadf4"},
    {"name": "Jours fériés", "url": "https://calendar.google.com/calendar/ical/fr.french%23holiday%40group.v.calendar.google.com/public/basic.ics", "color": "#a6da95"}
  ]
}
JSON
git status --short
