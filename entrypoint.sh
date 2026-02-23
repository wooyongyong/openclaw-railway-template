#!/bin/bash
echo "[entrypoint] === v18 starting ==="

# ---- 기본 설정 ----
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

# ---- 시크릿 로드: 환경변수 우선, 파일 폴백 ----
if [ -f "$SECRETS_FILE" ]; then
    echo "[entrypoint] secrets file found, using as fallback..."
    [ -z "$GEMINI_KEY" ] && GEMINI_KEY=$(grep '^GEMINI_KEY=' "$SECRETS_FILE" | cut -d'=' -f2-)
    [ -z "$TELEGRAM_TOKEN" ] && TELEGRAM_TOKEN=$(grep '^TELEGRAM_TOKEN=' "$SECRETS_FILE" | cut -d'=' -f2-)
fi
echo "[entrypoint] GEMINI_KEY loaded: $([ -n "$GEMINI_KEY" ] && echo YES || echo NO)"
echo "[entrypoint] TELEGRAM_TOKEN loaded: $([ -n "$TELEGRAM_TOKEN" ] && echo YES || echo NO)"

# ---- config 패치 함수 ----
patch_config() {
    if [ -f "$CONFIG_FILE" ]; then
        node -e "
        const fs = require('fs');
        const config = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
        let changed = false;

        // ---- gateway UI 설정 ----
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

        // ---- 텔레그램 플러그인 활성화 ----
        if (!config.plugins) config.plugins = {};
        if (!config.plugins.entries) config.plugins.entries = {};
        if (!config.plugins.entries.telegram || !config.plugins.entries.telegram.enabled) {
            config.plugins.entries.telegram = { enabled: true };
            changed = true;
            console.log('[entrypoint] telegram plugin enabled in config');
        }

        // ---- 텔레그램 채널 설정 ----
        if ('$TELEGRAM_TOKEN' && '$TELEGRAM_TOKEN' !== '') {
            if (!config.channels) config.channels = {};
            if (!config.channels.telegram) {
                config.channels.telegram = {
                    enabled: true,
                    botToken: '$TELEGRAM_TOKEN'
                };
                changed = true;
                console.log('[entrypoint] telegram channel configured');
            } else if (!config.channels.telegram.enabled) {
                config.channels.telegram.enabled = true;
                changed = true;
            }
        }

        // ---- v17에서 추가된 잘못된 키 정리 ----
        if (config.auth && config.auth.providers) {
            delete config.auth.providers;
            changed = true;
            console.log('[entrypoint] removed invalid auth.providers key');
        }
        if (config.auth && config.auth.fallback) {
            delete config.auth.fallback;
            changed = true;
            console.log('[entrypoint] removed invalid auth.fallback key');
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

# ---- 기존 유효 config가 있으면 재사용 ----
if [ -f "$CONFIG_FILE" ] && node -e "JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8')).gateway" 2>/dev/null; then
    echo "[entrypoint] existing valid config found, reusing it"
    patch_config
    exec gosu openclaw node src/server.js
fi

# ---- 시크릿 확인 ----
if [ -z "$GEMINI_KEY" ] || [ -z "$TELEGRAM_TOKEN" ]; then
    echo "[entrypoint] ERROR: secrets not available. Cannot run setup."
    echo "[entrypoint] Please set GEMINI_KEY and TELEGRAM_TOKEN env vars."
    exec gosu openclaw node src/server.js
fi

# ---- fresh setup ----
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
        \\"authChoice\\": \\"gemini-api-key\\",
        \\"authSecret\\": \\"${GEMINI_KEY}\\",
        \\"model\\": \\"google/gemini-2.0-flash\\",
        \\"telegramToken\\": \\"${TELEGRAM_TOKEN}\\",
        \\"flow\\": \\"quickstart\\"
    }" > /tmp/setup-result.json 2>&1

echo "[entrypoint] setup result: $(cat /tmp/setup-result.json)"

# config 패치
patch_config

echo "[entrypoint] setup done, waiting for node..."
wait $NODE_PID
