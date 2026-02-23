#!/bin/bash
echo "[entrypoint] === v15 starting ==="

# --- 기본 설정 ---
chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi
rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$STATE_DIR/openclaw.json"
SECRETS_FILE="/data/.secrets"

# --- 시크릿 파일에서 키 읽기 ---
# 키는 /data/.secrets 파일에 저장됨 (볼륨이므로 GitHub에 노출 안됨)
# 파일 형식:
#   GEMINI_KEY=AIzaSy...
#   TELEGRAM_TOKEN=8355...
if [ -f "$SECRETS_FILE" ]; then
  echo "[entrypoint] reading secrets from volume..."
  GEMINI_KEY=$(grep '^GEMINI_KEY=' "$SECRETS_FILE" | cut -d'=' -f2-)
  TELEGRAM_TOKEN=$(grep '^TELEGRAM_TOKEN=' "$SECRETS_FILE" | cut -d'=' -f2-)
  echo "[entrypoint] GEMINI_KEY loaded: $([ -n "$GEMINI_KEY" ] && echo YES || echo NO)"
  echo "[entrypoint] TELEGRAM_TOKEN loaded: $([ -n "$TELEGRAM_TOKEN" ] && echo YES || echo NO)"
else
  echo "[entrypoint] WARNING: /data/.secrets not found!"
  echo "[entrypoint] To create it, use Railway shell:"
  echo "[entrypoint]   railway shell"
  echo "[entrypoint]   echo 'GEMINI_KEY=your_key_here' > /data/.secrets"
  echo "[entrypoint]   echo 'TELEGRAM_TOKEN=your_token_here' >> /data/.secrets"
  echo "[entrypoint]   chmod 600 /data/.secrets"
  GEMINI_KEY=""
  TELEGRAM_TOKEN=""
fi

# --- config 패치 함수 ---
patch_config() {
  if [ -f "$CONFIG_FILE" ]; then
    node -e "
      const fs = require('fs');
      const config = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
      let changed = false;
      if (!config.gateway) config.gateway = {};
      if (!config.gateway.controlUi) config.gateway.controlUi = {};
      if (!config.gateway.controlUi.dangerouslyDisableDeviceAuth) {
        config.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
        changed = true;
      }
      if (!config.gateway.controlUi.allowInsecureAuth) {
        config.gateway.controlUi.allowInsecureAuth = true;
        changed = true;
      }
      if (!config.gateway.trustedProxies) config.gateway.trustedProxies = [];
      if (!config.gateway.trustedProxies.includes('100.64.0.0/10')) {
        config.gateway.trustedProxies.push('100.64.0.0/10');
        changed = true;
      }
      if (changed) {
        fs.writeFileSync('$CONFIG_FILE', JSON.stringify(config, null, 2));
        console.log('[entrypoint] config patched successfully');
      } else {
        console.log('[entrypoint] config already patched');
      }
    " 2>&1
    chown openclaw:openclaw "$CONFIG_FILE"
  fi
}

# --- 기존 유효 config가 있으면 재사용 ---
if [ -f "$CONFIG_FILE" ] && node -e "JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8')).gateway" 2>/dev/null; then
  echo "[entrypoint] existing valid config found, reusing it"
  patch_config
  exec gosu openclaw node src/server.js
fi

# --- 시크릿 확인 ---
if [ -z "$GEMINI_KEY" ] || [ -z "$TELEGRAM_TOKEN" ]; then
  echo "[entrypoint] ERROR: secrets not available. Cannot run setup."
  echo "[entrypoint] Please create /data/.secrets file first."
  echo "[entrypoint] Starting wrapper in setup-only mode..."
  exec gosu openclaw node src/server.js
fi

# --- fresh setup ---
echo "[entrypoint] no valid config, running fresh setup..."
[ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"

gosu openclaw node src/server.js &
NODE_PID=$!
trap "kill -TERM $NODE_PID; wait $NODE_PID" TERM INT

echo "[entrypoint] waiting for wrapper to be ready..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/setup/healthz > /dev/null 2>&1; then
    echo "[entrypoint] wrapper is ready!"
    break
  fi
  sleep 2
done

echo "[entrypoint] calling /setup/api/run ..."
curl -s -X POST http://localhost:8080/setup/api/run \
  -u ":${SETUP_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "{
    \"authChoice\": \"gemini-api-key\",
    \"authSecret\": \"${GEMINI_KEY}\",
    \"model\": \"google/gemini-2.0-flash\",
    \"telegramToken\": \"${TELEGRAM_TOKEN}\",
    \"flow\": \"quickstart\"
  }" > /tmp/setup-result.json 2>&1

echo "[entrypoint] setup result: $(cat /tmp/setup-result.json)"

# config 패치
patch_config

echo "[entrypoint] setup done, waiting for node..."
wait $NODE_PID
