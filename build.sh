#!/bin/bash
# Builds TapShortcuts.app and signs it.
#
# The signature is not about security: macOS ties the login item and the app's
# granted permissions to it. Without one they are lost on every rebuild.
set -euo pipefail
cd "$(dirname "$0")"

APP="TapShortcuts.app"
# Staged in a temporary folder outside the Desktop: it syncs with iCloud, and
# the file provider stamps files with attributes codesign rejects.
PROJECT="$(pwd)"
STAGE="$(mktemp -d /tmp/tapshortcuts-build.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
BIN="$STAGE/$APP/Contents/MacOS/TapShortcuts"

echo "==> building"
mkdir -p "$STAGE/$APP/Contents/MacOS" "$STAGE/$APP/Contents/Resources"
# main.swift must come last: Swift looks for the entry point there.
swiftc -O -o "$BIN" \
    $(ls Sources/*.swift | grep -v 'main\.swift$') Sources/main.swift \
    -framework AppKit -framework ServiceManagement
cp Info.plist "$STAGE/$APP/Contents/Info.plist"

xattr -cr "$STAGE/$APP"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID|Apple Development/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
    echo "==> signing ($IDENTITY)"
    codesign --force --deep --options runtime --sign "$IDENTITY" "$STAGE/$APP"
else
    echo "==> no signing certificate found, signing ad-hoc"
    codesign --force --deep --sign - "$STAGE/$APP"
fi

if codesign --verify --strict "$STAGE/$APP" 2>/dev/null; then
    echo "==> signature is valid"
else
    echo "==> ERROR: the signature failed verification"
    exit 1
fi

echo "==> installing"
rm -rf "$PROJECT/$APP"
ditto "$STAGE/$APP" "$PROJECT/$APP"
if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/$APP"
    ditto "$STAGE/$APP" "/Applications/$APP"
    echo "    /Applications/$APP"
fi
echo "Done: $PROJECT/$APP"
