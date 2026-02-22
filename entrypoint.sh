#!/bin/bash
set -e

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# ============================================
# 자동 설정: 환경변수로 openclaw.json 직접 생성
# ============================================
STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
CONFIG_FILE="$STATE_DIR/openclaw.json"
GW_PORT="${INTERNAL_GATEWAY_PORT:-18789}"
GW_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-defaulttoken123}"

if [ "${OPENCLAW_AUTO_CONFIG}" = "true" ]; then
  echo "[entrypoint] OPENCLAW_AUTO_CONFIG detected, writing config..." >&2

  mkdir -p "$STATE_DIR"
  mkdir -p "$WORKSPACE_DIR"
  chown -R openclaw:openclaw "$STATE_DIR"
  chown -R openclaw:openclaw "$WORKSPACE_DIR"

  # Telegram 설정 블록
  TELEGRAM_BLOCK=""
  if [ -n "$OPENCLAW_TELEGRAM_TOKEN" ]; then
    TELEGRAM_BLOCK=$(cat <<TEOF
    "telegram": {
      "enabled": true,
      "botToken": "$OPENCLAW_TELEGRAM_TOKEN",
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    }
TEOF
)
  fi

  # 모델 블록
  MODEL_ID="${OPENCLAW_MODEL:-google/gemini-2.0-flash}"

  # Auth provider 결정
  AUTH_PROVIDER="google"
  case "$OPENCLAW_AUTH_CHOICE" in
    apiKey) AUTH_PROVIDER="anthropic" ;;
    openai-api-key) AUTH_PROVIDER="openai" ;;
    gemini-api-key) AUTH_PROVIDER="google" ;;
    openrouter-api-key) AUTH_PROVIDER="openrouter" ;;
  esac

  # openclaw.json 직접 작성
  cat > "$CONFIG_FILE" <<EOF
{
  "version": 1,
  "gateway": {
    "auth": {
      "type": "token",
      "token": "$GW_TOKEN"
    },
    "controlUi": {
      "allowInsecureAuth": true
    },
    "trustedProxies": ["127.0.0.1"],
    "bind": "loopback",
    "port": $GW_PORT
  },
  "models": {
    "default": "$MODEL_ID"
  },
  "auth": {
    "provider": "$AUTH_PROVIDER",
    "apiKey": "${OPENCLAW_AUTH_SECRET:-}"
  },
  "channels": {
    $TELEGRAM_BLOCK
  },
  "workspace": "$WORKSPACE_DIR",
  "stateDir": "$STATE_DIR"
}
EOF

  chown openclaw:openclaw "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "[entrypoint] Config written to $CONFIG_FILE" >&2
fi

exec gosu openclaw node src/server.js
