#!/bin/sh
# Regenerates the brand images in assets/ from the vector logo in Sources/UI/Logo.swift:
# AppIcon.icns, the README logo (logo.png, logo-dark.png) and the DMG window (dmg-background.tiff, dmg-slot.png).
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp scripts/make_icon.swift "$tmp/main.swift"  # top-level code must live in main.swift
swiftc -O Sources/UI/Logo.swift "$tmp/main.swift" -o "$tmp/make_icon"
mkdir -p "$tmp/AppIcon.iconset" assets
"$tmp/make_icon" "$tmp/AppIcon.iconset"
for f in logo.png logo-dark.png dmg-background.tiff dmg-slot.png; do mv "$tmp/AppIcon.iconset/$f" assets/; done
mv "$tmp/AppIcon.iconset/menubar_preview.png" "$tmp/menubar_preview.png"
iconutil -c icns "$tmp/AppIcon.iconset" -o assets/AppIcon.icns
[ -n "${PREVIEW_DIR:-}" ] && cp "$tmp/AppIcon.iconset/icon_512x512@2x.png" "$tmp/menubar_preview.png" "$PREVIEW_DIR/"
echo "wrote assets/AppIcon.icns, logo.png, logo-dark.png, dmg-background.tiff, dmg-slot.png"
