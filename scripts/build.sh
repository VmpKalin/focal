#!/bin/zsh
# Builds Focal.app into ./build. Usage: scripts/build.sh [--install]
#   --install  copies the app to ~/Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Focal.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Focal "$APP/Contents/MacOS/Focal"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# A stable signing identity keeps the Accessibility permission across rebuilds;
# ad-hoc signing would make macOS ask again after every build.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Focal 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Focal.app
  cp -R "$APP" ~/Applications/Focal.app
  open ~/Applications/Focal.app
  echo "Installed to ~/Applications/Focal.app and launched"
fi
