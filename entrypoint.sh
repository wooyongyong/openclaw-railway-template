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
  rm -f "$CONFIG_FILE"
fi

# 자동 설정: wrapper 시작 후 /setup API 호출
if [ "${OPENCLAW_AUTO_CONFIG}" = "true" ] && [ ! -f "$CONFIG_FILE" ]; then
  (
    # wrapper가 준비될 때까지 대기
    for i in $(seq 1 30); do
      if curl -sf http://localhost:8080/setup/healthz > /dev/null 2>&1; then
        break
      fi
      sleep 2
    done

    # /setup/api/run 호출 (웹 UI의 Run Setup과 동일)
    curl -s -X POST http://localhost:8080/setup/api/run \
      -H "Content-Type: application/json" \
      -H "X-Setup-Password: ${SETUP_PASSWORD}" \
      -d "{
        \"authChoice\": \"${OPENCLAW_AUTH_CHOICE}\",
        \"authSecret\": \"${OPENCLAW_AUTH_SECRET}\",
        \"model\": \"${OPENCLAW_MODEL}\",
        \"telegramToken\": \"${OPENCLAW_TELEGRAM_TOKEN}\",
        \"flow\": \"quickstart\"
      }" > /tmp/setup-result.json 2>&1

    cat /tmp/setup-result.json >&2
  ) &
fi

exec gosu openclaw node src/server.js
