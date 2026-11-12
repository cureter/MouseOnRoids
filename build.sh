#!/bin/zsh
# Baut MouseOnRoids.app
#   ./build.sh           → bauen und nach ~/Applications installieren
#   ./build.sh release   → Universal-Build (Intel + Apple Silicon) als ZIP in dist/
set -e
cd "$(dirname "$0")"

MODE=${1:-install}
NAME=MouseOnRoids
APP=build/$NAME.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

# App-Icon aus dem 1024-px-PNG erzeugen
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

if [[ $MODE == release ]]; then
    ARCHS=(x86_64 arm64)
else
    ARCHS=($(uname -m))
fi
BINS=()
for arch in $ARCHS; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
        -o "build/$NAME-$arch" Sources/*.swift
    BINS+=("build/$NAME-$arch")
done
lipo -create $BINS -output "$APP/Contents/MacOS/$NAME"

# Mit einem lokalen Zertifikat signieren, falls vorhanden (dann bleibt die
# Bedienungshilfen-Erlaubnis über neue Builds hinweg erhalten), sonst ad hoc.
CERT_NAME=${SIGN_IDENTITY:-"SanftScroll Local Signing"}
IDENTITY=$(security find-identity -p codesigning | awk -v n="\"$CERT_NAME\"" 'index($0, n) {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"

if [[ $MODE == release ]]; then
    mkdir -p dist
    ZIP="dist/$NAME-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Release: $ZIP"
    exit 0
fi

DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x $NAME 2>/dev/null || true
rm -rf "$DEST/$NAME.app"
cp -R "$APP" "$DEST/"
echo "Installiert: $DEST/$NAME.app"
