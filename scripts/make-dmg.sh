#!/bin/sh
# Builds the release app and packs it into build/Bose-Mute-Microphone-<version>.dmg:
# the app plus a shortcut to /Applications, so installing is a drag and drop.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh >/dev/null
APP=build/Bose-Mute-Microphone.app
VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
DMG="build/Bose-Mute-Microphone-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Bose-Mute-Microphone $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "$DMG"
