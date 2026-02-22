#!/bin/bash

echo "[entrypoint] === v11 starting ==="

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$STATE_DIR/openclaw.json"

# 기존 config 삭제
if [ -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] removing existing config for clean setup"
  rm -f "$CONFIG_FILE"
fi

# wrapper를 백그라운드로 시작
gosu openclaw node src/server.js &
NODE_PID=$!
trap "kill -TERM $NODE_PID; wait $NODE_PID" TERM INT

# wrapper 준비 대기
echo "[entrypoint] waiting for wrapper to be ready..."
READY="false"
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/setup/healthz > /dev/null 2>&1; then
    echo "[entrypoint] wrapper is ready!"
    READY="true"
    break
  fi
  sleep 2
done

if [ "$READY" = "true" ]; then
  echo "[entrypoint] calling /setup/api/run ..."
  RESULT=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8080/setup/api/run \
    -u ":${SETUP_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d '{
      "authChoice": "gemini-api-key",
      "authSecret": "AIzaSyBxy-Oif5KxzwMMIjtMM57z6Q4hll1OQJk",
      "model": "google/gemini-2.0-flash",
      "telegramToken": "8355049814:AAEZwbNrmOyo81thKbjjRtDio4wa1rt-VE8",
      "flow": "quickstart"
    }')
  echo "[entrypoint] setup result: $RESULT"
else
  echo "[entrypoint] ERROR: wrapper did not become ready in 60s"
fi

echo "[entrypoint] setup phase complete, waiting for node..."
wait $NODE_PID
