#!/bin/bash

echo "[entrypoint] === v9 starting ==="

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$STATE_DIR/openclaw.json"

# 기존 config 삭제 (깨끗하게 재설정)
if [ -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] removing existing config for clean setup"
  rm -f "$CONFIG_FILE"
fi

# 디버그: 모든 환경변수 출력
echo "[entrypoint] === env debug ==="
echo "[entrypoint] SETUP_PASSWORD set: $([ -n "$SETUP_PASSWORD" ] && echo YES || echo NO)"
echo "[entrypoint] OPENCLAW_AUTH_CHOICE=${OPENCLAW_AUTH_CHOICE}"
echo "[entrypoint] OPENCLAW_AUTH_SECRET set: $([ -n "$OPENCLAW_AUTH_SECRET" ] && echo YES || echo NO)"
echo "[entrypoint] OPENCLAW_MODEL=${OPENCLAW_MODEL}"
echo "[entrypoint] OPENCLAW_TELEGRAM_TOKEN set: $([ -n "$OPENCLAW_TELEGRAM_TOKEN" ] && echo YES || echo NO)"
echo "[entrypoint] PORT=${PORT}"
echo "[entrypoint] all OPENCLAW vars:"
env | grep -i openclaw | sed 's/=.*/=***/' || true
echo "[entrypoint] ==================="

# wrapper를 백그라운드로 시작
gosu openclaw node src/server.js &
NODE_PID=$!
trap "kill -TERM $NODE_PID; wait $NODE_PID" TERM INT

# 무조건 자동 설정 실행 (환경변수 체크 없음)
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
  # 환경변수가 비어있으면 하드코딩된 기본값 사용
  AUTH_CHOICE="${OPENCLAW_AUTH_CHOICE:-gemini-api-key}"
  AUTH_SECRET="${OPENCLAW_AUTH_SECRET}"
  MODEL="${OPENCLAW_MODEL:-google/gemini-2.0-flash}"
  TELEGRAM="${OPENCLAW_TELEGRAM_TOKEN}"
  PASS="${SETUP_PASSWORD}"

  echo "[entrypoint] calling /setup/api/run (authChoice=$AUTH_CHOICE, model=$MODEL)"
  RESULT=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8080/setup/api/run \
    -u ":${PASS}" \
    -H "Content-Type: application/json" \
    -d "{
      \"authChoice\": \"${AUTH_CHOICE}\",
      \"authSecret\": \"${AUTH_SECRET}\",
      \"model\": \"${MODEL}\",
      \"telegramToken\": \"${TELEGRAM}\",
      \"flow\": \"quickstart\"
    }")
  echo "[entrypoint] setup result: $RESULT"
else
  echo "[entrypoint] ERROR: wrapper did not become ready in 60s"
fi

echo "[entrypoint] setup phase complete, waiting for node..."
wait $NODE_PID
