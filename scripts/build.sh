#!/bin/sh
# Release build → ./TAUdo.app (run tests first with: scripts/build.sh test)
set -eu
cd "$(dirname "$0")/.."
xcodegen generate -q
if [ "${1:-}" = test ]; then
  xcodebuild -project TAUdo.xcodeproj -scheme TAUdo -derivedDataPath build -quiet test
fi
xcodebuild -project TAUdo.xcodeproj -scheme TAUdo -configuration Release -derivedDataPath build -quiet build
rm -rf TAUdo.app
cp -R build/Build/Products/Release/TAUdo.app TAUdo.app
echo "built $(pwd)/TAUdo.app"
