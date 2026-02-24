#!/bin/bash

# v25 - Fix models array format (objects not strings)
echo "=== OpenClaw Railway Entrypoint v25 ==="
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
  models: {
    providers: {}
  },
  agents: {
    defaults: {
      model: {
        primary: 'google/gemini-2.0-flash'
      }
    }
  },
  channels: {},
  browser: {
    defaultProfile: 'openclaw',
    profiles: {
      openclaw: {
        color: '#FF6600',
        cdpPort: 9222
      }
    }
  }
};

if (geminiKey) {
  config.models.providers.google = {
    apiKey: geminiKey,
    api: 'google-generative-ai',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    models: [{ name: 'gemini-2.0-flash' }]
  };
}

if (telegramToken) {
  config.channels.telegram = {
    enabled: true,
    botToken: telegramToken,
    dmPolicy: 'open',
    allowFrom: ['*']
  };
}

const configPath = process.argv[1];
fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('Config written to ' + configPath);
console.log(JSON.stringify(config, null, 2));
" "$CONFIG_FILE"

# Setup HOME and openclaw config directory
export HOME="/home/openclaw"
mkdir -p "$HOME/.openclaw"
cp "$CONFIG_FILE" "$HOME/.openclaw/openclaw.json" || true

echo "Config ready at $CONFIG_FILE"
echo "Gateway port: $GW_PORT"

# Start gateway
echo "=== Starting OpenClaw Gateway ==="
exec openclaw gateway --port "$GW_PORT"
