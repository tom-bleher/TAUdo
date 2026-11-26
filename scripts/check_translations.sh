#!/bin/sh
# Lists UI strings that have no Hebrew translation in Sources/he.lproj (exit 1 if any).
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
xcodegen generate -q
xcodebuild -exportLocalizations -project TAUdo.xcodeproj -localizationPath "$tmp" -exportLanguage he >/dev/null 2>&1
python3 - "$tmp" <<'PY'
import glob, html, re, sys
x = open(glob.glob(sys.argv[1] + "/**/*.xliff", recursive=True)[0]).read()
units = re.findall(r'<trans-unit id="(.*?)"[^>]*>\s*<source>.*?</source>\s*(?:<target[^>]*>(.*?)</target>)?', x, re.S)
# Strings that are deliberately not translated (names, code, URLs, format-only).
keep = {"CFBundleDisplayName", "CFBundleName", "%@ — %@",
        "https://moodle.tau.ac.il/…/calendar/export_execute.php?…"}
missing = [html.unescape(k) for k, t in units if not t and html.unescape(k) not in keep]
print("\n".join(missing) if missing else "All strings translated.")
sys.exit(1 if missing else 0)
PY
