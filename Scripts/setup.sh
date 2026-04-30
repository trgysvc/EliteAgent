#!/bin/zsh

# 🛸 EliteAgent v7.0 Setup Script
# "Native Sovereign" - Automated Environment Preparation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "${BLUE}🛸 Initializing EliteAgent v7.0 Environment...${NC}"

# 1. Hardware Check (Apple Silicon)
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    echo "${RED}❌ Error: EliteAgent requires Apple Silicon (M1/M2/M3/M4).${NC}"
    exit 1
fi
echo "${GREEN}✅ Hardware: Apple Silicon detected.${NC}"

# 2. OS Check (macOS 15+)
OS_VER=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$OS_VER" -lt 15 ]]; then
    echo "${RED}❌ Error: EliteAgent requires macOS 15.0 or later.${NC}"
    exit 1
fi
echo "${GREEN}✅ OS: macOS $OS_VER detected.${NC}"

# 3. Xcode Check (Xcode 16+)
if ! xcode-select -p >/dev/null 2>&1; then
    echo "${RED}❌ Error: Xcode command line tools not found.${NC}"
    exit 1
fi
XCODE_VER=$(xcodebuild -version | head -n 1 | cut -d' ' -f2 | cut -d. -f1)
if [[ "$XCODE_VER" -lt 16 ]]; then
    echo "${RED}❌ Error: EliteAgent requires Xcode 16.0 or later.${NC}"
    exit 1
fi
echo "${GREEN}✅ Xcode: Version $XCODE_VER detected.${NC}"

# 4. Workspace Preparation
WORKSPACE_DIR="$HOME/Workspaces/EliteAgent"
if [[ ! -d "$WORKSPACE_DIR" ]]; then
    echo "${BLUE}📂 Creating standard workspace at $WORKSPACE_DIR...${NC}"
    mkdir -p "$WORKSPACE_DIR"
fi
echo "${GREEN}✅ Workspace: Ready.${NC}"

# 5. Vault Configuration
CONFIG_DIR="$HOME/Library/Application Support/EliteAgent"
VAULT_PATH="$CONFIG_DIR/vault.plist"

if [[ ! -d "$CONFIG_DIR" ]]; then
    mkdir -p "$CONFIG_DIR"
fi

if [[ ! -f "$VAULT_PATH" ]]; then
    echo "${BLUE}🔑 Generating vault.plist template...${NC}"
    cat <<EOF > "$VAULT_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>providers</key>
    <array>
        <dict>
            <key>id</key>
            <string>openrouter</string>
            <key>name</key>
            <string>OpenRouter</string>
            <key>apiKey</key>
            <string>YOUR_API_KEY_HERE</string>
            <key>modelName</key>
            <string>google/gemini-2.0-flash-001</string>
        </dict>
    </array>
    <key>mcpServers</key>
    <array>
        <!-- Add your MCP servers here -->
    </array>
    <key>isWorkspaceIsolationEnabled</key>
    <true/>
</dict>
</plist>
EOF
    echo "${GREEN}✅ Vault: Template created at $VAULT_PATH.${NC}"
    echo "${BLUE}👉 Action Required: Open $VAULT_PATH and add your API keys.${NC}"
else
    echo "${GREEN}✅ Vault: Existing configuration found.${NC}"
fi

# 6. Dependency Sync
echo "${BLUE}📦 Syncing Swift Packages...${NC}"
swift package resolve

echo "\n${GREEN}🚀 EliteAgent v7.0 Setup Complete!${NC}"
echo "--------------------------------------------------"
echo "1. Open EliteAgent.xcodeproj in Xcode."
echo "2. Build and Run (Cmd+R)."
echo "3. Grant Accessibility permissions when prompted."
echo "--------------------------------------------------"
