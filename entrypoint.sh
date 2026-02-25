#!/bin/bash

# v33 - Fix: add color to browser profile (required by schema)
# Error was: browser.profiles.openclaw.color: expected string, received undefined

echo "=== OpenClaw Railway Entrypoint v33 ==="
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

# Browser user data directory
BROWSER_USER_DATA="$OPENCLAW_STATE_DIR/browser/openclaw/user-data"
mkdir -p "$BROWSER_USER_DATA"

# Start headless Chromium in background
echo "Starting headless Chromium on port 18800..."
CDP_PORT=18800

# Find chromium binary
CHROMIUM_BIN=""
for bin in chromium-browser chromium google-chrome-stable google-chrome; do
  if command -v "$bin" &>/dev/null; then
    CHROMIUM_BIN="$bin"
    break
  fi
done

# Also check Playwright's chromium
if [ -z "$CHROMIUM_BIN" ]; then
  PW_CHROME=$(find "$PLAYWRIGHT_BROWSERS_PATH" -name "chrome" -type f 2>/dev/null | head -1)
  if [ -n "$PW_CHROME" ]; then
    CHROMIUM_BIN="$PW_CHROME"
  fi
fi

if [ -n "$CHROMIUM_BIN" ]; then
  echo "Found browser: $CHROMIUM_BIN"
  "$CHROMIUM_BIN" \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --remote-debugging-port=$CDP_PORT \
    --user-data-dir="$BROWSER_USER_DATA" \
    about:blank &
  CHROMIUM_PID=$!
  echo "Chromium started with PID $CHROMIUM_PID on CDP port $CDP_PORT"
  sleep 2
else
  echo "WARNING: No Chromium binary found! Browser features will be unavailable."
fi

# Build openclaw.json using node
echo "Building config..."
node -e "
const fs = require('fs');
const port = parseInt(process.env.PORT || '8080', 10);
const geminiKey = process.env.GEMINI_API_KEY || process.env.GEMINI_KEY || '';
const telegramToken = process.env.TELEGRAM_BOT_TOKEN || process.env.TELEGRAM_TOKEN || '';
const naverId = process.env.NAVER_ID || '';
const naverPw = process.env.NAVER_PW || '';

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
  browser: {
    defaultProfile: 'openclaw',
    headless: true,
    noSandbox: true,
    profiles: {
      openclaw: {
        cdpUrl: 'http://127.0.0.1:18800',
        color: '#4A90D9'
      }
    }
  },
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

// Set API keys via env section
const envVars = {};
if (geminiKey) envVars.GEMINI_API_KEY = geminiKey;
if (naverId) envVars.NAVER_ID = naverId;
if (naverPw) envVars.NAVER_PW = naverPw;

if (Object.keys(envVars).length > 0) {
  config.env = { vars: envVars };
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

# Also setup browser user data in home
mkdir -p "$HOME/.openclaw/browser/openclaw/user-data"

echo "Config ready at $CONFIG_FILE"
echo "Gateway port: $GW_PORT"

# Start gateway
echo "=== Starting OpenClaw Gateway ==="
exec openclaw gateway --port "$GW_PORT"
