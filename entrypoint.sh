#!/bin/bash

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# ============================================
# 자동 설정: openclaw CLI로 onboard + config
# server.js의 /setup/api/run과 동일한 방식
# ============================================
STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
CONFIG_FILE="$STATE_DIR/openclaw.json"
ENTRY="${OPENCLAW_ENTRY:-/usr/local/lib/node_modules/openclaw/dist/entry.js}"
GW_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(openssl rand -hex 32)}"
GW_PORT="${INTERNAL_GATEWAY_PORT:-18789}"

# 이전에 잘못 만든 config 삭제
if [ -f "$CONFIG_FILE" ] && grep -q '"version"' "$CONFIG_FILE" 2>/dev/null; then
  rm -f "$CONFIG_FILE"
fi

if [ "${OPENCLAW_AUTO_CONFIG}" = "true" ] && [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$STATE_DIR" "$WORKSPACE_DIR"
  chown -R openclaw:openclaw "$STATE_DIR" "$WORKSPACE_DIR"

  # Step 1: openclaw onboard (server.js buildOnboardArgs와 동일)
  ONBOARD_CMD="node $ENTRY onboard --non-interactive --accept-risk --json --no-install-daemon --skip-health --workspace $WORKSPACE_DIR --gateway-bind loopback --gateway-port $GW_PORT --gateway-auth token --gateway-token $GW_TOKEN --flow quickstart"

  if [ -n "$OPENCLAW_AUTH_CHOICE" ] && [ -n "$OPENCLAW_AUTH_SECRET" ]; then
    ONBOARD_CMD="$ONBOARD_CMD --auth-choice $OPENCLAW_AUTH_CHOICE"
    case "$OPENCLAW_AUTH_CHOICE" in
      gemini-api-key)    ONBOARD_CMD="$ONBOARD_CMD --gemini-api-key $OPENCLAW_AUTH_SECRET" ;;
      apiKey)            ONBOARD_CMD="$ONBOARD_CMD --anthropic-api-key $OPENCLAW_AUTH_SECRET" ;;
      openai-api-key)    ONBOARD_CMD="$ONBOARD_CMD --openai-api-key $OPENCLAW_AUTH_SECRET" ;;
      openrouter-api-key) ONBOARD_CMD="$ONBOARD_CMD --openrouter-api-key $OPENCLAW_AUTH_SECRET" ;;
    esac
  fi

  export OPENCLAW_STATE_DIR="$STATE_DIR"
  export OPENCLAW_WORKSPACE_DIR="$WORKSPACE_DIR"

  gosu openclaw $ONBOARD_CMD > /tmp/onboard.log 2>&1
  ONBOARD_EXIT=$?
  cat /tmp/onboard.log >&2

  if [ $ONBOARD_EXIT -eq 0 ] && [ -f "$CONFIG_FILE" ]; then
    # Step 2: gateway config (server.js와 동일)
    gosu openclaw node "$ENTRY" config set gateway.controlUi.allowInsecureAuth true 2>&1
    gosu openclaw node "$ENTRY" config set gateway.auth.token "$GW_TOKEN" 2>&1
    gosu openclaw node "$ENTRY" config set --json gateway.trustedProxies '["127.0.0.1"]' 2>&1

    # Step 3: model 설정
    if [ -n "$OPENCLAW_MODEL" ]; then
      gosu openclaw node "$ENTRY" models set "$OPENCLAW_MODEL" 2>&1
    fi

    # Step 4: Telegram 설정
    if [ -n "$OPENCLAW_TELEGRAM_TOKEN" ]; then
      gosu openclaw node "$ENTRY" config set --json channels.telegram "{\"enabled\":true,\"botToken\":\"$OPENCLAW_TELEGRAM_TOKEN\",\"dmPolicy\":\"pairing\",\"groupPolicy\":\"allowlist\",\"streamMode\":\"partial\"}" 2>&1
    fi
  fi
fi

exec gosu openclaw node src/server.js
