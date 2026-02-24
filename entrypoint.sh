#!/bin/bash
set -e

# v21 - No heredoc, uses node to build JSON config
echo "=== OpenClaw Railway Entrypoint v21 ==="
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

# Build openclaw.json using node (no heredoc issues)
echo "Building config..."
node -e "
const fs = require('fs');
const port = parseInt(process.env.INTERNAL_GATEWAY_PORT || '8080', 10);
const geminiKey = process.env.GEMINI_API_KEY || process.env.GEMINI_KEY || '';
const telegramToken = process.env.TELEGRAM_BOT_TOKEN || process.env.TELEGRAM_TOKEN || '';

const config = {
  gateway: {
      port: port,
          bind: 'lan',
              controlUi: {
                    dangerouslyDisableDeviceAuth: true,
                          allowInsecureAuth: true
                              },
                                  trustedProxies: ['loopback', 'private', '100.64.0.0/10']
                                    },
                                      agents: {
                                          main: {
                                                model: 'google/gemini-2.0-flash'
                                                    }
                                                      },
                                                        channels: {},
                                                          browser: {
                                                              defaultProfile: 'openclaw',
                                                                  profiles: {
                                                                        openclaw: {
                                                                                headless: true,
                                                                                        noSandbox: true
                                                                                              }
                                                                                                  }
                                                                                                    }
                                                                                                    };
                                                                                                    
                                                                                                    if (geminiKey) {
                                                                                                      config.auth = { google: { apiKey: geminiKey } };
                                                                                                      }
                                                                                                      
                                                                                                      if (telegramToken) {
                                                                                                        config.channels.telegram = { default: { botToken: telegramToken } };
                                                                                                        }
                                                                                                        
                                                                                                        fs.writeFileSync('$CONFIG_FILE', JSON.stringify(config, null, 2));
                                                                                                        console.log('Config written to $CONFIG_FILE');
                                                                                                        "
                                                                                                        
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
