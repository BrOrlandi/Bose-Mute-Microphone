#!/bin/sh
# Builds the app, installs it to ~/Applications and (re)starts it.
# On first launch the app registers itself as a Login Item (menu: "Iniciar com o Mac").
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh
DEST="$HOME/Applications/Bose-Mute-Microphone.app"
mkdir -p "$HOME/Applications"
# Quit a running copy first; quitting restores any microphones it had muted.
osascript -e 'tell application id "local.brunoorlandi.BoseMuteMicrophone" to quit' 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R build/Bose-Mute-Microphone.app "$DEST"
open "$DEST"
echo "Instalado em $DEST"
