#!/bin/bash

# EliteAgent Archive & Notarization Automation
# Usage: ./ArchiveAutomation.sh "Developer ID Application: Your Name (ID)" "AppSpecificPasswordName"

SIGNING_IDENTITY=$1
NOTARY_PROFILE=$2
APP_NAME="EliteAgent"
BUILD_DIR="./build"
XCCONFIG="./Resources/Config/Release.xcconfig"

echo "🚀 Starting EliteAgent build & notarization pipeline..."

# 1. Clean and Build
echo "📦 Building $APP_NAME in Release mode..."
swift build -c release --arch arm64 --arch x86_64

# 2. Package App Bundle (Simplified structure for CLI)
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"
cp "./.build/release/$APP_NAME" "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/"
cp "./EliteAgent.entitlements" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/"

# 3. Sign the Bundle
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "✍️ Signing $APP_NAME with identity: $SIGNING_IDENTITY"
    codesign --deep --force --options runtime --entitlements ./EliteAgent.entitlements --sign "$SIGNING_IDENTITY" "$BUILD_DIR/$APP_NAME.app"
else
    echo "⚠️ Skipping signing (No identity provided)"
fi

# 4. Create ZIP for Notarization
echo "🤐 Creating archive for notarization..."
ditto -c -k --sequesterRsrc --keepParent "$BUILD_DIR/$APP_NAME.app" "$BUILD_DIR/$APP_NAME.zip"

# 5. Notarize
if [ -n "$NOTARY_PROFILE" ]; then
    echo "🛂 Sending to Apple Notary Service..."
    xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    
    echo "📋 Stapling notarization ticket..."
    xcrun stapler staple "$BUILD_DIR/$APP_NAME.app"
else
    echo "⚠️ Skipping notarization (No profile provided)"
fi

echo "✅ Pipeline complete. App is ready in $BUILD_DIR/$APP_NAME.app"
