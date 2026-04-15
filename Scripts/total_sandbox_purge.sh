#!/bin/bash

# EliteAgent Total Sandbox Purge Script
# This MUST be run to ensure the OS recognizes the app as non-sandboxed.

BUNDLE_ID="com.trgysvc.EliteAgent"
CONTAINER_DIR="$HOME/Library/Containers/$BUNDLE_ID"

echo "🧹 Starting EliteAgent Sandbox Purge..."

# 1. Kill any running instances
echo "🛑 Terminating EliteAgent processes..."
pkill -x "EliteAgent" 2>/dev/null
pkill -x "EliteAgentXPC" 2>/dev/null

# 2. Clear Legacy Container
if [ -d "$CONTAINER_DIR" ]; then
    echo "🗑️  Deleting legacy container: $CONTAINER_DIR"
    rm -rf "$CONTAINER_DIR"
else
    echo "✅ No legacy container found at $CONTAINER_DIR"
fi

# 3. Clear Shared Cache
SHARED_DATA="$HOME/Library/Group Containers/$BUNDLE_ID"
if [ -d "$SHARED_DATA" ]; then
    echo "🗑️  Deleting shared group data: $SHARED_DATA"
    rm -rf "$SHARED_DATA"
fi

# 4. Clear DerivedData (CRITICAL for security/signing cache)
echo "🗑️  Clearing Xcode DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/EliteAgent-*

# 5. Reset Launch Services
echo "🔄 Resetting Launch Services cache..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

echo "✨ Purge complete. Building EliteAgent in non-sandboxed mode..."

# 5. Rebuild (Optional but recommended)
swift build

echo "🚀 DONE. You can now launch EliteAgent and it will be 100% UNRESTRICTED."
