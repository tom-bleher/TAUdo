#!/bin/zsh
# Builds dist/<version>/TAUdo-<version>.dmg and the Sparkle feed appcast.xml next to it.
#   scripts/release.sh             build, test, package, sign the feed
#   scripts/release.sh --publish   then create GitHub release v<version> with both files
#
# The app's SUFeedURL is the latest release's appcast.xml, so publishing is what ships an update.
# Bump CFBundleVersion in project.yml for every release: Sparkle compares it.
#
# Signing: ad-hoc by default (on first launch macOS blocks it until System Settings › Privacy & Security ›
# Open Anyway). With
#   SIGN_ID="Developer ID Application: …" [NOTARY_PROFILE=<notarytool profile>]
# the app and DMG are signed with the hardened runtime and, with a profile, notarized and stapled.
#
# The feed is signed with the EdDSA key in the login keychain under account "taudo"
# (its public half is SUPublicEDKey in project.yml). Back it up outside the repo, e.g. into a password manager;
# without it no update can ship:
#   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account taudo -x ~/taudo-sparkle-key
set -euo pipefail
cd "${0:A:h:h}"
die() { print -u2 "error: $*"; exit 1 }
publish=0
[[ "${1:-}" == --publish ]] && publish=1

# Publish exactly what's on GitHub: the tag must point at the code that was built.
if (( publish )); then
  [[ -z "$(git status --porcelain)" ]] || die "commit your changes first"
  gh auth status >/dev/null 2>&1 || die "gh isn't logged in (gh auth login)"
  git fetch -q origin main
  head=$(git rev-parse HEAD)
  [[ "$head" == "$(git rev-parse origin/main)" ]] || die "HEAD isn't origin/main: push, or check out main"
fi

scripts/build.sh test
app=TAUdo.app
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $app/Contents/Info.plist)
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $app/Contents/Info.plist)
if (( publish )); then
  ! gh release view "v$version" >/dev/null 2>&1 || die "v$version is already released: bump the version in project.yml"
  # Sparkle only offers a higher CFBundleVersion than the one installed.
  feed=$(/usr/libexec/PlistBuddy -c "Print SUFeedURL" $app/Contents/Info.plist)
  published=$( { curl -fsL "$feed" || true } | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | sort -n | tail -1)
  (( build > ${published:-0} )) || die "CFBundleVersion $build isn't above the published $published: bump it in project.yml"
fi

work=$(mktemp -d)
trap 'hdiutil detach "$work/mnt" -quiet -force 2>/dev/null || true; rm -rf "$work"' EXIT

notarize() {  # file to submit, file to staple
  [[ -n "${NOTARY_PROFILE:-}" ]] || return 0
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$2"
}
if [[ -n "${SIGN_ID:-}" ]]; then
  # Inside out, as Sparkle documents (sparkle-project.org/documentation/sandboxing), then the app with its
  # entitlements (calendar access, which the hardened runtime otherwise refuses).
  sign() { codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$@" }
  sparkle=$app/Contents/Frameworks/Sparkle.framework
  sign $sparkle/Versions/B/XPCServices/Installer.xpc
  sign --preserve-metadata=entitlements $sparkle/Versions/B/XPCServices/Downloader.xpc
  sign $sparkle/Versions/B/Autoupdate
  sign $sparkle/Versions/B/Updater.app
  sign $sparkle
  sign --entitlements TAUdo.entitlements $app
  zip=$work/TAUdo.zip
  ditto -c -k --keepParent $app "$zip"
  notarize "$zip" $app
fi

out=dist/$version
dmg=$out/TAUdo-$version.dmg
rm -rf "$out"; mkdir -p "$out"

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
  gh release create "v$version" "$dmg" "$out/appcast.xml" --target "$head" --title "TAUdo $version" --generate-notes
fi
