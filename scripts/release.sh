#!/bin/sh
# Builds a release zip in dist/.
#   scripts/release.sh                      ad-hoc signed (others must right-click › Open the first time)
#   SIGN_ID="Developer ID Application: …" NOTARY_PROFILE=<keychain profile> scripts/release.sh
#                                           signed with hardened runtime, notarized and stapled
# (create the profile once with: xcrun notarytool store-credentials <profile> --apple-id … --team-id …)
set -eu
cd "$(dirname "$0")/.."
scripts/build.sh test
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" TAUdo.app/Contents/Info.plist)
mkdir -p dist
zip="dist/TAUdo-$version.zip"
rm -f "$zip"
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" TAUdo.app
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    ditto -c -k --keepParent TAUdo.app "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple TAUdo.app
    rm "$zip"
  fi
fi
ditto -c -k --keepParent TAUdo.app "$zip"
echo "wrote $zip"
