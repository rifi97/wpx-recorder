#!/bin/sh
set -eu

swift build -c release

APP_DIR="outputs/WPXRecorder.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cp -f ".build/release/WPXRecorder" "$APP_DIR/Contents/MacOS/WPXRecorder"
cp -f "AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc signing makes the locally built app launchable without a developer account.
codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
