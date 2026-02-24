#!/bin/bash

# v31 - Fix: add controlUi.dangerouslyAllowHostHeaderOriginFallback for non-loopback bind
# Error was: non-loopback Control UI requires allowedOrigins or dangerouslyAllowHostHeaderOriginFallback

echo "=== OpenClaw Railway Entrypoint v31 ==="
echo "Starting at $(date -u)"

# Directories
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/data/openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"
mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR"

# Config file location
CONFIG_FILE="$OPENCLAW_STATE_DIR/openclaw.json"

# Use PORT (matches Dockerfile healthcheck on 8080)
GW_PORT="${PORT:-8080}"

# Build openclaw.json using node
echo "Building config..."
node -e "
const fs = require('fs');
const port = parseInt(process.env.PORT || '8080', 10);
const geminiKey = process.env.GEMINI_API_KEY || process.env.GEMINI_KEY || '';
const telegramToken = process.env.TELEGRAM_BOT_TOKEN || process.env.TELEGRAM_TOKEN || '';

const config = {
  agents: {
    defaults: {
      workspace: '/data/workspace',
      model: {
        primary: 'google/gemini-2.0-flash'
      }
    }
  },
  channels: {},
  gateway: {
    mode: 'local',
    port: port,
    bind: 'lan',
    controlUi: {
      enabled: true,
      dangerouslyAllowHostHeaderOriginFallback: true
    }
  }
};

// Set Gemini API key via env section
if (geminiKey) {
  config.env = {
    vars: {
      GEMINI_API_KEY: geminiKey
    }
  };
}

// Configure Telegram channel
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
