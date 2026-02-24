#!/bin/bash
set -e

# v20 - Simplified entrypoint with Playwright browser support
echo "=== OpenClaw Railway Entrypoint v20 ==="
echo "Starting at $(date -u)"

# Directories
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/data/openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"
mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR"

# Config file
CONFIG_DIR="$OPENCLAW_STATE_DIR"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
mkdir -p "$CONFIG_DIR"

# Resolve gateway port
GW_PORT="${INTERNAL_GATEWAY_PORT:-8080}"

# Build openclaw.json from env vars
echo "Building config..."
cat > "$CONFIG_FILE" << JSONEOF
{
  "gateway": {
      "port": $GW_PORT,
          "bind": "lan",
              "controlUi": {
                    "dangerouslyDisableDeviceAuth": true,
                          "allowInsecureAuth": true
                              },
                                  "trustedProxies": ["loopback", "private", "100.64.0.0/10"]
                                    },
                                      "agents": {
                                          "main": {
                                                "model": "google/gemini-2.0-flash"
                                                    }
                                                      },
                                                        "channels": {},
                                                          "browser": {
                                                              "defaultProfile": "openclaw",
                                                                  "profiles": {
                                                                        "openclaw": {
                                                                                "headless": true,
                                                                                        "noSandbox": true
                                                                                              }
                                                                                                  }
                                                                                                    }
                                                                                                    }
                                                                                                    JSONEOF
                                                                                                    
                                                                                                    # Add Gemini API key
                                                                                                    if [ -n "$GEMINI_API_KEY" ] || [ -n "$GEMINI_KEY" ]; then
                                                                                                      KEY="${GEMINI_API_KEY:-$GEMINI_KEY}"
                                                                                                        echo "Configuring Gemini..."
                                                                                                          node -e "
                                                                                                              const fs = require('fs');
                                                                                                                  const c = JSON.parse(fs.readFileSync('$CONFIG_FILE','utf8'));
                                                                                                                      c.auth = c.auth || {};
                                                                                                                          c.auth.google = { apiKey: '$KEY' };
                                                                                                                              fs.writeFileSync('$CONFIG_FILE', JSON.stringify(c, null, 2));
                                                                                                                                "
                                                                                                                                fi
                                                                                                                                
                                                                                                                                # Add Telegram
                                                                                                                                if [ -n "$TELEGRAM_BOT_TOKEN" ] || [ -n "$TELEGRAM_TOKEN" ]; then
                                                                                                                                  TOKEN="${TELEGRAM_BOT_TOKEN:-$TELEGRAM_TOKEN}"
                                                                                                                                    echo "Configuring Telegram..."
                                                                                                                                      node -e "
                                                                                                                                          const fs = require('fs');
                                                                                                                                              const c = JSON.parse(fs.readFileSync('$CONFIG_FILE','utf8'));
                                                                                                                                                  c.channels = c.channels || {};
                                                                                                                                                      c.channels.telegram = { default: { botToken: '$TOKEN' } };
                                                                                                                                                          fs.writeFileSync('$CONFIG_FILE', JSON.stringify(c, null, 2));
                                                                                                                                                            "
                                                                                                                                                            fi
                                                                                                                                                            
                                                                                                                                                            # Set HOME for openclaw CLI
                                                                                                                                                            export HOME="$OPENCLAW_STATE_DIR/.."
                                                                                                                                                            mkdir -p "$HOME/.openclaw"
                                                                                                                                                            cp "$CONFIG_FILE" "$HOME/.openclaw/openclaw.json" 2>/dev/null || ln -sf "$CONFIG_FILE" "$HOME/.openclaw/openclaw.json"
                                                                                                                                                            
                                                                                                                                                            echo "Config ready at $CONFIG_FILE"
                                                                                                                                                            echo "Browser profile: openclaw (headless Playwright)"
                                                                                                                                                            echo "Gateway port: $GW_PORT"
                                                                                                                                                            
                                                                                                                                                            # Start gateway
                                                                                                                                                            echo "=== Starting OpenClaw Gateway ==="
                                                                                                                                                            exec openclaw gateway --port "$GW_PORT"
