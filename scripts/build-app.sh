#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Codex Usage Board.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_DIR/UsageBoard" "$APP_DIR/Contents/MacOS/UsageBoard"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

ICONSET_DIR="$PROJECT_DIR/.build/UsageBoard.iconset"
mkdir -p "$ICONSET_DIR"
swift "$PROJECT_DIR/scripts/make-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR"

printf '\n作成しました: %s\n' "$APP_DIR"
