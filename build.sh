#!/bin/bash
# Builds Dockstep.app into ./build.
#
#   ./build.sh             development build for this Mac (ad-hoc signed)
#   ./build.sh --install   development build, copied to /Applications and (re)started
#   ./build.sh --release   release build for Apple silicon and Intel, zipped into ./dist:
#                          - signed with your "Developer ID Application" certificate if one is
#                            installed (or the identity in $SIGN_IDENTITY), otherwise ad-hoc
#                          - notarized and stapled if that signing worked and a notarytool
#                            keychain profile named "dockstep" (or $NOTARY_PROFILE) exists
#
# The version comes from the VERSION file; the build number is the git commit count.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
APP="build/Dockstep.app"

if [[ "$MODE" == "--release" ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        echo "warning: uncommitted changes; this release won't match a commit exactly" >&2
    fi
else
    ARCH_ARGS=(--arch "$(uname -m)")
fi

# All configurations share one output folder, so always build right before copying.
swift build -c release "${ARCH_ARGS[@]}" 2>&1 | grep -v "x86_64 architecture is deprecated" || true
BIN="$(swift build -c release "${ARCH_ARGS[@]}" --show-bin-path)/Dockstep"
[[ -x "$BIN" ]] || { echo "build failed" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dockstep"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$APP/Contents/Info.plist"

IDENTITY="-"
if [[ "$MODE" == "--release" ]]; then
    IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
    IDENTITY="${IDENTITY:--}"
fi
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP" >/dev/null
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict "$APP"
fi
echo "Built $APP $VERSION ($BUILD_NUMBER), $(lipo -archs "$APP/Contents/MacOS/Dockstep"), signed: $IDENTITY"

if [[ "$MODE" == "--install" ]]; then
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

if [[ "$MODE" == "--release" ]]; then
    mkdir -p dist
    ZIP="dist/Dockstep-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"

    PROFILE="${NOTARY_PROFILE:-dockstep}"
    if [[ "$IDENTITY" == "-" ]]; then
        echo "note: ad-hoc signed (no Developer ID certificate found), so not notarized." >&2
        echo "      People who download it must allow it once under" >&2
        echo "      System Settings › Privacy & Security › Open Anyway." >&2
    elif xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
        echo "Notarizing with Apple (usually takes a few minutes)…"
        xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
        xcrun stapler staple "$APP"
        rm -f "$ZIP"
        ditto -c -k --keepParent "$APP" "$ZIP"
        spctl --assess --type execute --verbose=2 "$APP"
    else
        echo "note: signed but not notarized: no notarytool profile \"$PROFILE\" found." >&2
        echo "      Create one with: xcrun notarytool store-credentials $PROFILE" >&2
    fi
    echo "Release: $ZIP"
    shasum -a 256 "$ZIP"
fi
