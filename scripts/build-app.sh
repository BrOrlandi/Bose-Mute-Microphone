#!/bin/sh
# Builds build/Bose-Mute-Microphone.app (release, ad-hoc signed, menu bar only).
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product BoseMuteMicrophone
APP=build/Bose-Mute-Microphone.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/BoseMuteMicrophone" "$APP/Contents/MacOS/BoseMuteMicrophone"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
