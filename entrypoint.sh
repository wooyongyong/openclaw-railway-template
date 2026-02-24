#!/bin/bash

# v22 - Fixed: removed set -e, fixed HOME path
echo "=== OpenClaw Railway Entrypoint v22 ==="
echo "Starting at $(date -u)"

# Directories
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/data/openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"
mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR"

# Config file location
CONFIG_FILE="$OPENCLAW_STATE_DIR/openclaw.json"

# Resolve gateway port
GW_PORT="${INTERNAL_GATEWAY_PORT:-8080}"

# Build openclaw.json using node
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
                                                                                                        
                                                                                                        const configPath = process.argv[1];
                                                                                                        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
                                                                                                        console.log('Config written to ' + configPath);
                                                                                                        " "$CONFIG_FILE"
                                                                                                        
                                                                                                        # Setup HOME and openclaw config directory
                                                                                                        export HOME="/home/openclaw"
                                                                                                        mkdir -p "$HOME/.openclaw"
                                                                                                        cp "$CONFIG_FILE" "$HOME/.openclaw/openclaw.json" || true
                                                                                                        
                                                                                                        echo "Config ready at $CONFIG_FILE"
                                                                                                        echo "Browser profile: openclaw (headless Playwright)"
                                                                                                        echo "Gateway port: $GW_PORT"
                                                                                                        
                                                                                                        # Start gateway
                                                                                                        echo "=== Starting OpenClaw Gateway ==="
                                                                                                        exec openclaw gateway --port "$GW_PORT"
