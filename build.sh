#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=build/Reformule.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
swiftc -O -target arm64-apple-macosx26.0 Sources/*.swift -o "$APP/Contents/MacOS/Reformule"
codesign --force --sign - "$APP"
if [ "$1" = "install" ]; then
  rm -rf "$HOME/Applications/Reformule.app"
  cp -R "$APP" "$HOME/Applications/"
  APP="$HOME/Applications/Reformule.app"
fi
echo "$APP"
