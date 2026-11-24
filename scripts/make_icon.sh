#!/bin/sh
# Regenerates assets/AppIcon.icns and the README logo (assets/logo.png, assets/logo-dark.png)
# from the vector logo in Sources/UI/Logo.swift.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp scripts/make_icon.swift "$tmp/main.swift"  # top-level code must live in main.swift
swiftc -O Sources/UI/Logo.swift "$tmp/main.swift" -o "$tmp/make_icon"
mkdir -p "$tmp/AppIcon.iconset" assets
"$tmp/make_icon" "$tmp/AppIcon.iconset"
mv "$tmp/AppIcon.iconset/logo.png" "$tmp/AppIcon.iconset/logo-dark.png" assets/
mv "$tmp/AppIcon.iconset/menubar_preview.png" "$tmp/menubar_preview.png"
iconutil -c icns "$tmp/AppIcon.iconset" -o assets/AppIcon.icns
[ -n "${PREVIEW_DIR:-}" ] && cp "$tmp/AppIcon.iconset/icon_512x512@2x.png" "$tmp/menubar_preview.png" "$PREVIEW_DIR/"
echo "wrote assets/AppIcon.icns, assets/logo.png, assets/logo-dark.png"
