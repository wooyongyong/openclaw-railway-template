#!/bin/bash

echo "[entrypoint] === v8 starting ==="

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# config 파일 경로 확인
STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$STATE_DIR/openclaw.json"
echo "[entrypoint] STATE_DIR=$STATE_DIR"
echo "[entrypoint] CONFIG_FILE=$CONFIG_FILE"
echo "[entrypoint] OPENCLAW_AUTO_CONFIG=${OPENCLAW_AUTO_CONFIG}"
echo "[entrypoint] config file exists: $([ -f "$CONFIG_FILE" ] && echo YES || echo NO)"

# 기존 config 무조건 삭제 (깨끗하게 재설정)
if [ -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] removing existing config file for clean setup"
  rm -f "$CONFIG_FILE"
fi

NEED_SETUP="false"
if [ "${OPENCLAW_AUTO_CONFIG}" = "true" ]; then
  NEED_SETUP="true"
fi
echo "[entrypoint] NEED_SETUP=$NEED_SETUP"

# wrapper를 백그라운드로 시작
gosu openclaw node src/server.js &
NODE_PID=$!

# SIGTERM을 node에 전달
trap "kill -TERM $NODE_PID; wait $NODE_PID" TERM INT

# 자동 설정 실행
if [ "$NEED_SETUP" = "true" ]; then
  echo "[entrypoint] waiting for wrapper to be ready..."

  READY="false"
  for i in $(seq 1 30); do
    HEALTH=$(curl -s http://localhost:8080/setup/healthz 2>&1)
    if [ $? -eq 0 ]; then
      echo "[entrypoint] wrapper is ready! health=$HEALTH"
      READY="true"
      break
    fi
    echo "[entrypoint] attempt $i - not ready yet"
    sleep 2
  done

  if [ "$READY" = "true" ]; then
    echo "[entrypoint] calling /setup/api/run ..."
    RESULT=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8080/setup/api/run \
      -u ":${SETUP_PASSWORD}" \
      -H "Content-Type: application/json" \
      -d "{
        \"authChoice\": \"${OPENCLAW_AUTH_CHOICE}\",
        \"authSecret\": \"${OPENCLAW_AUTH_SECRET}\",
        \"model\": \"${OPENCLAW_MODEL}\",
        \"telegramToken\": \"${OPENCLAW_TELEGRAM_TOKEN}\",
        \"flow\": \"quickstart\"
      }")
    echo "[entrypoint] setup result: $RESULT"
  else
    echo "[entrypoint] ERROR: wrapper did not become ready in 60s"
  fi
else
  echo "[entrypoint] skipping auto-config (OPENCLAW_AUTO_CONFIG is not true)"
fi

echo "[entrypoint] setup phase complete, waiting for node..."
wait $NODE_PID
