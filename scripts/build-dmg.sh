#!/bin/zsh
# Builds build/Zap.app and build/Zap-<version>.dmg (universal: Apple Silicon + Intel).
# Needs the Xcode command line tools: xcode-select --install

set -e

root=${0:A:h:h}
build=$root/build
app=$build/Zap.app
version=$(grep -m1 '^ZAP_VERSION=' $root/shell/zap.zsh | cut -d= -f2)

rm -rf $build
mkdir -p $app/Contents/MacOS $app/Contents/Resources

print "compiling…"
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target $arch-apple-macos13.0 \
    $root/app/ZapSetup.swift -o $build/Zap-$arch
done
lipo -create -output $app/Contents/MacOS/Zap $build/Zap-arm64 $build/Zap-x86_64
rm $build/Zap-arm64 $build/Zap-x86_64

cp $root/shell/zap.zsh $root/scripts/install.sh $app/Contents/Resources/
cp $root/assets/logo/zap-icon-1024.png $app/Contents/Resources/logo.png
cp $root/assets/flash/flash-*.png $app/Contents/Resources/

print "making the icon…"
iconset=$build/Zap.iconset
mkdir $iconset
for s in 16 32 128 256 512; do
  sips -z $s $s $root/assets/logo/zap-icon-1024.png --out $iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s * 2)) $((s * 2)) $root/assets/logo/zap-icon-1024.png --out $iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $iconset -o $app/Contents/Resources/Zap.icns
rm -rf $iconset

cat > $app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Zap</string>
  <key>CFBundleDisplayName</key><string>Zap</string>
  <key>CFBundleIdentifier</key><string>dev.louaibenhassine.zap</string>
  <key>CFBundleExecutable</key><string>Zap</string>
  <key>CFBundleIconFile</key><string>Zap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# ad-hoc signature; without a paid Apple developer ID this is as far as it goes
codesign --force --deep --sign - $app

print "packing the dmg…"
stage=$build/dmg
mkdir -p $stage
cp -R $app $stage/
ln -s /Applications $stage/Applications
hdiutil create -volname Zap -srcfolder $stage -ov -format UDZO $build/Zap-$version.dmg >/dev/null
rm -rf $stage

print "done: build/Zap-$version.dmg"
