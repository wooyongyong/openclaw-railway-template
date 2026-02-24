#!/bin/bash

# v28 - Config based on official OpenClaw docs (docs.openclaw.ai)
# Key changes: use 'agent' (singular), Google is built-in provider,
# no browser section needed, minimal config approach

echo "=== OpenClaw Railway Entrypoint v28 ==="
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

# Build openclaw.json using node (based on official config examples)
echo "Building config..."
node -e "
const fs = require('fs');
const port = parseInt(process.env.INTERNAL_GATEWAY_PORT || '8080', 10);
const geminiKey = process.env.GEMINI_API_KEY || process.env.GEMINI_KEY || '';
const telegramToken = process.env.TELEGRAM_BOT_TOKEN || process.env.TELEGRAM_TOKEN || '';

const config = {
  agent: {
    workspace: '/data/workspace',
    model: {
      primary: 'google/gemini-2.0-flash'
    }
  },
  channels: {},
  gateway: {
    port: port,
    bind: 'lan',
    controlUi: {
      enabled: true
    }
  }
};

// Set Gemini API key via env section if available
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
