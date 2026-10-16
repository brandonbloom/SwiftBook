#!/bin/bash
# Build RendererApp with plain SwiftPM for the iOS simulator, wrap it in a .app, install it.
set -eu
SPIKE=${SPIKE:?set SPIKE to the spike's working directory}
SIM=${SIM:?set SIM to a simulator's UDID}
cd "$SPIKE/DemoPkg"
swift build -q --product RendererApp --triple arm64-apple-ios18.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --scratch-path "$SPIKE/spmbuild"
"$SPIKE/bundle-app.sh" "$SPIKE/spmbuild/out/Products/Debug-iphonesimulator/RendererApp" "$SPIKE/out/RendererApp.app"
xcrun simctl install "$SIM" "$SPIKE/out/RendererApp.app"
