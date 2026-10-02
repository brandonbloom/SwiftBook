#!/bin/bash
# usage: bundle-app.sh <executable> <out.app>   -- wraps a SwiftPM-built iOS-simulator executable in a minimal .app
set -eu
exe=$1 app=$2
rm -rf "$app"; mkdir -p "$app"
SDKVER=$(xcrun --sdk iphonesimulator --show-sdk-version)
# SwiftPM stamps LC_BUILD_VERSION sdk = deployment target; UIKit/SwiftUI linked-on-or-after behavior keys off this.
vtool -set-build-version iossim 18.0 "$SDKVER" -replace -output "$app/RendererApp" "$exe"
cat > "$app/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.swiftbook.spike.renderer</string>
  <key>CFBundleExecutable</key><string>RendererApp</string>
  <key>CFBundleName</key><string>SwiftBookRenderer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>MinimumOSVersion</key><string>18.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key><dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
  </dict>
</dict></plist>
PL
codesign --force --sign - "$app" >/dev/null 2>&1
