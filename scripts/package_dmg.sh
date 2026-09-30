#!/usr/bin/env bash
# Package an .app into a compressed DMG with an /Applications symlink.
# Zero dependencies beyond macOS's built-in hdiutil.
#
#   scripts/package_dmg.sh path/to/MyApp.app [output.dmg]
set -euo pipefail

APP_PATH="${1:?usage: package_dmg.sh path/to/MyApp.app [output.dmg]}"
# Strip a trailing slash: BSD cp -R copies a directory's CONTENTS (not the
# directory) when the source ends in '/', which would silently produce a DMG
# without the .app bundle. zsh tab completion appends that slash.
APP_PATH="${APP_PATH%/}"
APP_NAME="$(basename "${APP_PATH}" .app)"
OUTPUT="${2:-${APP_NAME}.dmg}"

[ -d "${APP_PATH}" ] || { echo "error: '${APP_PATH}' is not an app bundle" >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

cp -R "${APP_PATH}" "${STAGING}/"
[ -d "${STAGING}/${APP_NAME}.app" ] || {
    echo "error: staging failed — '${STAGING}/${APP_NAME}.app' does not exist" >&2
    exit 1
}
ln -s /Applications "${STAGING}/Applications"

# hdiutil create intermittently fails with "Resource busy" on CI runners.
for attempt in 1 2 3; do
    if hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" -ov -format UDZO "${OUTPUT}"; then
        echo "Created ${OUTPUT}"
        exit 0
    fi
    if [ "${attempt}" -lt 3 ]; then
        echo "hdiutil create failed (attempt ${attempt}/3) — retrying in 5s" >&2
        sleep 5
    fi
done
echo "error: hdiutil create failed after 3 attempts" >&2
exit 1
