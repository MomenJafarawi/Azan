#!/bin/zsh
# Builds Azan (menu bar app + desktop widget) and installs it to /Applications.
# Builds in $TMPDIR because ExFAT "._" files break codesign.
set -e
cd "$(dirname "$0")"
STAGE="${TMPDIR:-/tmp}/azan-build"
APP="$STAGE/Azan.app"
WX="$APP/Contents/PlugIns/AzanWidget.appex"
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds" "$APP/Contents/Resources/Speech" "$WX/Contents/MacOS" "$WX/Contents/Resources" build

# universal: Apple Silicon + Intel
for ARCH in arm64 x86_64; do
  FLAGS=(-O -swift-version 5 -target $ARCH-apple-macos14.0)
  swiftc $FLAGS Shared/*.swift App/*.swift -o "$STAGE/Azan-$ARCH"
  swiftc $FLAGS -parse-as-library -application-extension -Xlinker -e -Xlinker _NSExtensionMain Shared/*.swift Widget/*.swift -o "$STAGE/AzanWidget-$ARCH"
done
lipo -create "$STAGE/Azan-arm64" "$STAGE/Azan-x86_64" -output "$STAGE/Azan-bin"
lipo -create "$STAGE/AzanWidget-arm64" "$STAGE/AzanWidget-x86_64" -output "$WX/Contents/MacOS/AzanWidget"

cp Resources/Sounds/*.mp3 "$APP/Contents/Resources/Sounds/"
cp Resources/Speech/*.m4a "$APP/Contents/Resources/Speech/"
cp Resources/adhkar.json "$APP/Contents/Resources/"
cp Resources/Fonts/Amiri-*.ttf "$APP/Contents/Resources/"
cp Resources/Fonts/Amiri-*.ttf "$WX/Contents/Resources/"
cp Info.plist "$APP/Contents/"
cp Widget/Info.plist "$WX/Contents/"

if [ ! -f build/AppIcon.icns ]; then
  swiftc -swift-version 5 Tools/MakeIcon.swift -o "$STAGE/makeicon"
  "$STAGE/makeicon" build/icon1024.png
  ICONSET="$STAGE/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/"

# manifest of every needed file (the app checks it at every start and repairs from a spare copy)
( cd "$APP/Contents/Resources" && find . -type f \( -name '*.mp3' -o -name '*.m4a' -o -name '*.json' -o -name '*.ttf' \) ! -name manifest.json ! -name '._*' | sed 's|^\./||' | sort | while read f; do printf '%s\t%s\n' "$f" "$(shasum -a 256 "$f" | cut -d' ' -f1)"; done ) | python3 -c "
import sys,json; print(json.dumps(dict(l.rstrip('\n').split('\t') for l in sys.stdin), ensure_ascii=False, indent=1))" > "$APP/Contents/Resources/manifest.json"

# everything must pass before anything is installed
"$STAGE/Azan-bin" --selftest "$PWD/Resources" "$APP/Contents/Resources"
mv "$STAGE/Azan-bin" "$APP/Contents/MacOS/Azan"

find "$APP" -name '._*' -delete
xattr -cr "$APP"
codesign --force --sign - --entitlements Widget/Widget.entitlements -r='designated => identifier "com.momen.azan.widget"' "$WX"
codesign --force --sign - -r='designated => identifier "com.momen.azan"' "$APP"

DEST=/Applications/Azan.app
pkill -x Azan 2>/dev/null || true
rm -rf "$DEST"
ditto --norsrc "$APP" "$DEST"
codesign --verify --deep --verbose "$DEST"
# let the system pick up the widget
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
pluginkit -a "$DEST/Contents/PlugIns/AzanWidget.appex" 2>/dev/null || true
echo "Installed to $DEST"

# portable package: DMG with the app, an installer, the Applications link and an Arabic guide
if [ "$1" = "dmg" ]; then
  VER=$(plutil -extract CFBundleShortVersionString raw Info.plist)
  PKG="$STAGE/dmg"; mkdir -p "$PKG" dist
  ditto "$APP" "$PKG/Azan.app"
  cp Packaging/install.command "$PKG/ثبّت أذان.command"
  cp "Packaging/اقرأني - طريقة التثبيت.txt" "$PKG/"
  ln -s /Applications "$PKG/Applications"
  find "$PKG" -name '._*' -delete
  rm -f "$STAGE/Azan.dmg"
  hdiutil create -volname "أذان $VER" -srcfolder "$PKG" -format UDZO -ov "$STAGE/Azan.dmg" >/dev/null
  cp "$STAGE/Azan.dmg" "dist/Azan-$VER-mac.dmg"
  echo "DMG: dist/Azan-$VER-mac.dmg ($(du -h "dist/Azan-$VER-mac.dmg" | cut -f1))"
fi
