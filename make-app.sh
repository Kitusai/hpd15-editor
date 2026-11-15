#!/bin/bash
# Fabrique « Editeur HPD15.app », universelle (Intel + Apple Silicon) sans Xcode complet :
# deux compilations (--triple arm64 puis x86_64) réunies par lipo.
# Si une architecture échoue, l'application est faite pour l'architecture de ce Mac seulement.
# Usage : ./make-app.sh   →   l'application est créée dans le dossier du projet.
set -o pipefail
cd "$(dirname "$0")"

APP="Editeur HPD15.app"
PRODUCT="HPD15"
ICON_SRC="Icon/AppIcon.png"
VERSION="1.0"
LOG="build-log.txt"
: > "$LOG"

build() {   # $1 = triple (vide = natif)
    if [ -n "$1" ]; then
        echo "→ Compilation release pour $1…"
        swift build -c release --product $PRODUCT --triple "$1" 2>&1 | tee -a "$LOG"
    else
        echo "→ Compilation release (architecture de ce Mac)…"
        swift build -c release --product $PRODUCT 2>&1 | tee -a "$LOG"
    fi
}
binpath() { # $1 = triple (vide = natif)
    if [ -n "$1" ]; then swift build -c release --product $PRODUCT --triple "$1" --show-bin-path
    else swift build -c release --product $PRODUCT --show-bin-path; fi
}

ARM="arm64-apple-macosx12.0"
X86="x86_64-apple-macosx12.0"
BINS=()
RES_DIR=""
for T in "$ARM" "$X86"; do
    if build "$T"; then
        P=$(binpath "$T")
        BINS+=("$P/$PRODUCT")
        [ -z "$RES_DIR" ] && RES_DIR="$P"
    else
        echo "  (échec pour $T : voir $LOG)"
    fi
done
if [ ${#BINS[@]} -eq 0 ]; then
    build "" || { echo "ÉCHEC : voir $LOG"; exit 1; }
    P=$(binpath "")
    BINS=("$P/$PRODUCT")
    RES_DIR="$P"
fi

echo "→ Création de l'application…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ ${#BINS[@]} -ge 2 ]; then
    lipo -create -output "$APP/Contents/MacOS/$PRODUCT" "${BINS[@]}" || { echo "ÉCHEC lipo"; exit 1; }
else
    cp "${BINS[0]}" "$APP/Contents/MacOS/$PRODUCT"
fi
# Ressources du cœur (catalogue des sons)
if [ -d "$RES_DIR/EditeurHPD15_HPD15Core.bundle" ]; then
    cp -R "$RES_DIR/EditeurHPD15_HPD15Core.bundle" "$APP/Contents/Resources/"
else
    echo "ATTENTION : EditeurHPD15_HPD15Core.bundle introuvable dans $RES_DIR"
fi

ICON_KEY=""
if [ -f "$ICON_SRC" ]; then
    echo "→ Icône…"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z $d $d "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Editeur HPD15</string>
    <key>CFBundleDisplayName</key><string>Editeur HPD15</string>
    <key>CFBundleExecutable</key><string>$PRODUCT</string>
    <key>CFBundleIdentifier</key><string>io.github.kitusai.hpd15-editor</string>
    $ICON_KEY
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Signature « ad hoc » : suffisante pour lancer l'application sur ce Mac.
codesign --force --deep --sign - "$APP" 2>&1 | tail -2

echo "✓ Terminé : $(pwd)/$APP"
echo "  architectures : $(lipo -archs "$APP/Contents/MacOS/$PRODUCT" 2>/dev/null)"
open -R "$APP"
