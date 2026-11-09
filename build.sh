#!/bin/bash
# Builds Dockstep.app into ./build.
#   ./build.sh            build only
#   ./build.sh --install  build, copy to /Applications and (re)start it
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Dockstep"

APP="build/Dockstep.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dockstep"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    # Quit a running copy first; it restores the built-in ⌘⇥ on the way out.
    if pgrep -x Dockstep >/dev/null; then
        pkill -TERM -x Dockstep || true
        for _ in {1..20}; do pgrep -x Dockstep >/dev/null || break; sleep 0.1; done
    fi
    rm -rf /Applications/Dockstep.app
    ditto "$APP" /Applications/Dockstep.app
    open /Applications/Dockstep.app
    echo "Installed and started /Applications/Dockstep.app"
fi
