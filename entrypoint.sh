#!/bin/bash

echo "[entrypoint] === v13 starting ==="

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$STATE_DIR/openclaw.json"

# config이 이미 있고 유효하면 재사용 (볼륨에 저장된 설정)
if [ -f "$CONFIG_FILE" ] && node -e "JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8')).gateway" 2>/dev/null; then
  echo "[entrypoint] existing valid config found, reusing it"

  # Railway proxy 패치가 안 되어있으면 추가
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
    if (!config.gateway.trustedProxies) config.gateway.trustedProxies = [];
    if (!config.gateway.trustedProxies.includes('100.64.0.0/10')) {
      config.gateway.trustedProxies.push('100.64.0.0/10');
      changed = true;
    }

    if (changed) {
      fs.writeFileSync('$CONFIG_FILE', JSON.stringify(config, null, 2));
      console.log('[entrypoint] config patched with Railway proxy settings');
    } else {
      console.log('[entrypoint] config already has Railway proxy settings');
    }
  " 2>&1
  chown openclaw:openclaw "$CONFIG_FILE"

  # wrapper 시작 (이미 설정됨 -> 바로 게이트웨이 시작)
  exec gosu openclaw node src/server.js

else
  echo "[entrypoint] no valid config, running fresh setup..."

  # 잘못된 config 삭제
  [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"

  # wrapper를 백그라운드로 시작
  gosu openclaw node src/server.js &
  NODE_PID=$!
  trap "kill -TERM $NODE_PID; wait $NODE_PID" TERM INT

  # wrapper 준비 대기
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
    -d '{
      "authChoice": "gemini-api-key",
      "authSecret": "AIzaSyBxy-Oif5KxzwMMIjtMM57z6Q4hll1OQJk",
      "model": "google/gemini-2.0-flash",
      "telegramToken": "8355049814:AAEZwbNrmOyo81thKbjjRtDio4wa1rt-VE8",
      "flow": "quickstart"
    }' > /tmp/setup-result.json 2>&1
  echo "[entrypoint] setup result: $(cat /tmp/setup-result.json)"

  # config 파일 패치
  if [ -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] patching config for Railway proxy..."
    node -e "
      const fs = require('fs');
      const config = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
      if (!config.gateway) config.gateway = {};
      if (!config.gateway.controlUi) config.gateway.controlUi = {};
      config.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
      if (!config.gateway.trustedProxies) config.gateway.trustedProxies = [];
      if (!config.gateway.trustedProxies.includes('100.64.0.0/10')) {
        config.gateway.trustedProxies.push('100.64.0.0/10');
      }
      fs.writeFileSync('$CONFIG_FILE', JSON.stringify(config, null, 2));
      console.log('[entrypoint] config patched successfully');
    " 2>&1
    chown openclaw:openclaw "$CONFIG_FILE"
  fi

  echo "[entrypoint] setup done, waiting for node..."
  wait $NODE_PID
fi
