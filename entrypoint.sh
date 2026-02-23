#!/bin/bash
echo "[entrypoint] === v16 starting ==="

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

# ---- 시크릿 파일에서 키 읽기 ----
# 키는 /data/.secrets 파일에 저장됨 (볼륨이므로 GitHub에 노출 안됨)
# 파일 형식:
#   GEMINI_KEY=AIzaSy...
#   TELEGRAM_TOKEN=8355...
#   CLAUDE_KEY=sk-ant-api03-...
#   PERPLEXITY_KEY=pplx-...
if [ -f "$SECRETS_FILE" ]; then
    echo "[entrypoint] reading secrets from volume..."
    GEMINI_KEY=$(grep '^GEMINI_KEY=' "$SECRETS_FILE" | cut -d'=' -f2-)
    TELEGRAM_TOKEN=$(grep '^TELEGRAM_TOKEN=' "$SECRETS_FILE" | cut -d'=' -f2-)
    CLAUDE_KEY=$(grep '^CLAUDE_KEY=' "$SECRETS_FILE" | cut -d'=' -f2-)
    PERPLEXITY_KEY=$(grep '^PERPLEXITY_KEY=' "$SECRETS_FILE" | cut -d'=' -f2-)
    echo "[entrypoint] GEMINI_KEY loaded: $([ -n "$GEMINI_KEY" ] && echo YES || echo NO)"
    echo "[entrypoint] TELEGRAM_TOKEN loaded: $([ -n "$TELEGRAM_TOKEN" ] && echo YES || echo NO)"
    echo "[entrypoint] CLAUDE_KEY loaded: $([ -n "$CLAUDE_KEY" ] && echo YES || echo NO)"
    echo "[entrypoint] PERPLEXITY_KEY loaded: $([ -n "$PERPLEXITY_KEY" ] && echo YES || echo NO)"
else
    echo "[entrypoint] WARNING: /data/.secrets not found!"
    echo "[entrypoint] To create it, use Railway shell:"
    echo "[entrypoint]   railway shell"
    echo "[entrypoint]   echo 'GEMINI_KEY=your_key_here' > /data/.secrets"
    echo "[entrypoint]   echo 'TELEGRAM_TOKEN=your_token_here' >> /data/.secrets"
    echo "[entrypoint]   echo 'CLAUDE_KEY=your_key_here' >> /data/.secrets"
    echo "[entrypoint]   echo 'PERPLEXITY_KEY=your_key_here' >> /data/.secrets"
    echo "[entrypoint]   chmod 600 /data/.secrets"
    GEMINI_KEY=""
    TELEGRAM_TOKEN=""
    CLAUDE_KEY=""
    PERPLEXITY_KEY=""
fi

# ---- config 패치 함수 ----
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

        // ---- Claude API 키 추가 ----
        if ('$CLAUDE_KEY' && '$CLAUDE_KEY' !== '') {
            if (!config.auth) config.auth = {};
            if (!config.auth.providers) config.auth.providers = {};
            config.auth.providers['anthropic-api-key'] = {
                authSecret: '$CLAUDE_KEY',
                model: 'anthropic/claude-sonnet-4-20250514'
            };
            changed = true;
            console.log('[entrypoint] Claude API key configured');
        }

        // ---- Perplexity API 키 추가 ----
        if ('$PERPLEXITY_KEY' && '$PERPLEXITY_KEY' !== '') {
            if (!config.auth) config.auth = {};
            if (!config.auth.providers) config.auth.providers = {};
            config.auth.providers['perplexity-api-key'] = {
                authSecret: '$PERPLEXITY_KEY',
                model: 'perplexity/sonar-pro'
            };
            changed = true;
            console.log('[entrypoint] Perplexity API key configured');
        }

        // ---- 폴백 순서: Gemini -> Perplexity -> Claude ----
        const fallbackOrder = [];
        if (config.auth && config.auth.providers) {
            if (config.auth.providers['gemini-api-key']) fallbackOrder.push('gemini-api-key');
            if (config.auth.providers['perplexity-api-key']) fallbackOrder.push('perplexity-api-key');
            if (config.auth.providers['anthropic-api-key']) fallbackOrder.push('anthropic-api-key');
        }
        if (fallbackOrder.length > 1) {
            if (!config.auth.fallback) config.auth.fallback = {};
            config.auth.fallback.order = fallbackOrder;
            changed = true;
            console.log('[entrypoint] fallback order set:', fallbackOrder.join(' -> '));
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
    echo "[entrypoint] Please create /data/.secrets file first."
    echo "[entrypoint] Starting wrapper in setup-only mode..."
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
