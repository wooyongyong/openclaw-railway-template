#!/bin/bash

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# 이전에 잘못 만든 config 삭제
STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$STATE_DIR/openclaw.json"
if [ -f "$CONFIG_FILE" ] && grep -q '"version"' "$CONFIG_FILE" 2>/dev/null; then
  echo "[entrypoint] removing invalid config file"
  rm -f "$CONFIG_FILE"
fi

NEED_SETUP="false"
if [ "${OPENCLAW_AUTO_CONFIG}" = "true" ] && [ ! -f "$CONFIG_FILE" ]; then
  NEED_SETUP="true"
fi

# wrapper를 백그라운드로 시작
gosu openclaw node src/server.js &
NODE_PID=$!

# SIGTERM을 node에 전달
trap "kill -TERM $NODE_PID; wait $NODE_PID" TERM INT

# 자동 설정 실행 (포그라운드 - 로그가 보임)
if [ "$NEED_SETUP" = "true" ]; then
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
    echo "[entrypoint] calling /setup/api/run with Basic auth..."
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
    echo "[entrypoint] ERROR: wrapper did not become ready in 60 seconds"
  fi
fi

# node 프로세스가 끝날 때까지 대기
wait $NODE_PID
