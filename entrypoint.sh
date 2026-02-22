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
# 자동 설정 (OPENCLAW_AUTO_CONFIG=true 일 때)
# /setup 페이지 없이 환경변수로 자동 구성
# ============================================
STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$STATE_DIR/openclaw.json"
ENTRY="/usr/local/lib/node_modules/openclaw/dist/entry.js"

if [ "${OPENCLAW_AUTO_CONFIG}" = "true" ] && [ ! -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] Auto-configuring OpenClaw..."

  mkdir -p "$STATE_DIR"
  mkdir -p "${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"

  # Gateway 토큰 생성 (없으면 랜덤)
  GW_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(openssl rand -hex 32)}"

  # Onboarding 실행
  ONBOARD_ARGS=(
    "onboard"
    "--non-interactive"
    "--accept-risk"
    "--json"
    "--no-install-daemon"
    "--skip-health"
    "--workspace" "${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
    "--gateway-bind" "loopback"
    "--gateway-port" "${INTERNAL_GATEWAY_PORT:-18789}"
    "--gateway-auth" "token"
    "--gateway-token" "$GW_TOKEN"
  )

  # AI 인증 설정
  if [ -n "$OPENCLAW_AUTH_CHOICE" ] && [ -n "$OPENCLAW_AUTH_SECRET" ]; then
    ONBOARD_ARGS+=("--auth-choice" "$OPENCLAW_AUTH_CHOICE")
    case "$OPENCLAW_AUTH_CHOICE" in
      gemini-api-key)
        ONBOARD_ARGS+=("--gemini-api-key" "$OPENCLAW_AUTH_SECRET")
        ;;
      apiKey)
        ONBOARD_ARGS+=("--anthropic-api-key" "$OPENCLAW_AUTH_SECRET")
        ;;
      openai-api-key)
        ONBOARD_ARGS+=("--openai-api-key" "$OPENCLAW_AUTH_SECRET")
        ;;
      openrouter-api-key)
        ONBOARD_ARGS+=("--openrouter-api-key" "$OPENCLAW_AUTH_SECRET")
        ;;
    esac
  fi

  echo "[entrypoint] Running onboarding..."
  gosu openclaw node "$ENTRY" "${ONBOARD_ARGS[@]}" || echo "[entrypoint] Onboarding returned non-zero, continuing..."

  # Gateway 설정
  echo "[entrypoint] Configuring gateway..."
  gosu openclaw node "$ENTRY" config set gateway.controlUi.allowInsecureAuth true || true
  gosu openclaw node "$ENTRY" config set gateway.auth.token "$GW_TOKEN" || true
  gosu openclaw node "$ENTRY" config set --json gateway.trustedProxies '["127.0.0.1"]' || true

  # 모델 설정
  if [ -n "$OPENCLAW_MODEL" ]; then
    echo "[entrypoint] Setting model: $OPENCLAW_MODEL"
    gosu openclaw node "$ENTRY" models set "$OPENCLAW_MODEL" || true
  fi

  # Telegram 설정
  if [ -n "$OPENCLAW_TELEGRAM_TOKEN" ]; then
    echo "[entrypoint] Configuring Telegram..."
    TELEGRAM_JSON="{\"enabled\":true,\"botToken\":\"$OPENCLAW_TELEGRAM_TOKEN\",\"dmPolicy\":\"pairing\",\"groupPolicy\":\"allowlist\",\"streamMode\":\"partial\"}"
    gosu openclaw node "$ENTRY" config set --json channels.telegram "$TELEGRAM_JSON" || true
  fi

  echo "[entrypoint] Auto-configuration complete!"
fi

exec gosu openclaw node src/server.js
