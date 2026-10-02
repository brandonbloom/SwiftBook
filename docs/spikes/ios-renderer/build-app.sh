#!/bin/bash
# Build RendererApp with plain SwiftPM for the iOS simulator, wrap it in a .app, install it.
set -eu
SPIKE=/private/tmp/claude-501/-Users-bbloom-Projects-SwiftBook/0fb6b314-9885-43b1-9687-5e66c3785e65/scratchpad/ios-renderer-spike
SIM=${SIM:-46C0D949-E428-49AF-9693-9930A53AB57A}
cd "$SPIKE/DemoPkg"
swift build -q --product RendererApp --triple arm64-apple-ios18.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --scratch-path "$SPIKE/spmbuild"
"$SPIKE/bundle-app.sh" "$SPIKE/spmbuild/out/Products/Debug-iphonesimulator/RendererApp" "$SPIKE/out/RendererApp.app"
xcrun simctl install "$SIM" "$SPIKE/out/RendererApp.app"
