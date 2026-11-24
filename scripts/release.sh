#!/bin/zsh
# Builds dist/<version>/TAUdo-<version>.dmg and the Sparkle feed appcast.xml next to it.
#   scripts/release.sh             build, test, package, sign the feed
#   scripts/release.sh --publish   then create GitHub release v<version> with both files
#
# The app's SUFeedURL is the latest release's appcast.xml, so publishing is what ships an update.
# Bump CFBundleVersion in project.yml for every release: Sparkle compares it.
#
# Signing: ad-hoc by default (first launch needs right-click › Open). With
#   SIGN_ID="Developer ID Application: …" [NOTARY_PROFILE=<notarytool profile>]
# the app and DMG are signed with the hardened runtime and, with a profile, notarized and stapled.
#
# The feed is signed with the EdDSA key in the login keychain under account "taudo"
# (its public half is SUPublicEDKey in project.yml). Back it up; without it no update can ship:
#   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account taudo -x taudo-sparkle-key
set -euo pipefail
cd "${0:A:h:h}"
publish=0
[[ "${1:-}" == --publish ]] && publish=1

scripts/build.sh test
app=TAUdo.app
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $app/Contents/Info.plist)
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $app/Contents/Info.plist)
if (( publish )); then
  [[ -z "$(git status --porcelain)" ]] || { print -u2 "error: commit your changes first"; exit 1 }
  ! gh release view "v$version" >/dev/null 2>&1 || { print -u2 "error: v$version is already released: bump the version"; exit 1 }
fi

notarize() {  # file to submit, file to staple
  [[ -n "${NOTARY_PROFILE:-}" ]] || return 0
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$2"
}
if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" $app
  zip=$(mktemp -d)/TAUdo.zip
  ditto -c -k --keepParent $app "$zip"
  notarize "$zip" $app
fi

out=dist/$version
dmg=$out/TAUdo-$version.dmg
rm -rf "$out"; mkdir -p "$out"
work=$(mktemp -d)
trap 'hdiutil detach "$work/mnt" -quiet -force 2>/dev/null || true; rm -rf "$work"' EXIT

# A drag-to-Applications window. Window size and icon positions match scripts/make_icon.swift.
mkdir -p "$work/stage/.background"
ditto $app "$work/stage/TAUdo.app"
swift scripts/dmg-alias.swift "$work/stage/Applications" assets/dmg-slot.png
cp assets/dmg-background.tiff "$work/stage/.background/background.tiff"
cp assets/AppIcon.icns "$work/stage/.VolumeIcon.icns"
hdiutil create -srcfolder "$work/stage" -volname TAUdo -fs HFS+ -format UDRW -ov "$work/rw.dmg" >/dev/null
hdiutil attach "$work/rw.dmg" -readwrite -noverify -noautoopen -nobrowse -mountpoint "$work/mnt" >/dev/null
SetFile -a C "$work/mnt"
uv run --quiet --with ds-store --with mac-alias scripts/dmg-layout.py "$work/mnt" .background/background.tiff \
  --window 600x330 --icon-size 112 --place TAUdo.app=135,150 --place Applications=335,150
codesign --verify --deep --strict "$work/mnt/TAUdo.app"
hdiutil detach "$work/mnt" -quiet
hdiutil convert "$work/rw.dmg" -format ULFO -o "$dmg" >/dev/null
if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$dmg"
  notarize "$dmg" "$dmg"
fi

# Sparkle's feed: one item for this DMG, signed with the EdDSA key.
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast --account taudo \
  --download-url-prefix "https://github.com/tom-bleher/TAUdo/releases/download/v$version/" \
  -o "$out/appcast.xml" "$out"
grep -q 'sparkle:edSignature' "$out/appcast.xml" || { print -u2 "error: appcast.xml is not signed"; exit 1 }
print "wrote $dmg and $out/appcast.xml (version $version, build $build)"

if (( publish )); then
  gh release create "v$version" "$dmg" "$out/appcast.xml" --title "TAUdo $version" --generate-notes
fi
