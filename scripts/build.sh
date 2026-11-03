#!/bin/zsh
# Builds Focal.app into ./build. Usage: scripts/build.sh [--install]
#   --install  copies the app to ~/Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

# Assemble and sign outside the project: iCloud-synced folders (Desktop/Documents) attach
# extended attributes that codesign rejects.
STAGE=$(mktemp -d)/Focal.app
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp .build/release/Focal "$STAGE/Contents/MacOS/Focal"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
xattr -cr "$STAGE"

# A stable signing identity keeps the Accessibility permission across rebuilds;
# ad-hoc signing would make macOS ask again after every build.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
codesign --force --options runtime --sign "${IDENTITY:--}" "$STAGE"
codesign --verify --strict "$STAGE"

rm -rf build/Focal.app
mkdir -p build
ditto "$STAGE" build/Focal.app
echo "Built build/Focal.app (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Focal 2>/dev/null && sleep 1 || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Focal.app
  ditto "$STAGE" ~/Applications/Focal.app
  codesign --verify --strict ~/Applications/Focal.app
  open ~/Applications/Focal.app
  echo "Installed to ~/Applications/Focal.app and launched"
fi
