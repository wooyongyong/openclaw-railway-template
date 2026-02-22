#!/bin/bash

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# 무조건 설정 파일 생성
mkdir -p /data/.openclaw /data/workspace
chown -R openclaw:openclaw /data/.openclaw /data/workspace

printf '{"version":1,"gateway":{"auth":{"type":"token","token":"%s"},"controlUi":{"allowInsecureAuth":true},"trustedProxies":["127.0.0.1"],"bind":"loopback","port":18789},"models":{"default":"%s"},"auth":{"provider":"google","apiKey":"%s"},"channels":{"telegram":{"enabled":true,"botToken":"%s","dmPolicy":"pairing","groupPolicy":"allowlist","streamMode":"partial"}},"workspace":"/data/workspace","stateDir":"/data/.openclaw"}' \
  "${OPENCLAW_GATEWAY_TOKEN:-defaulttoken}" \
  "${OPENCLAW_MODEL:-google/gemini-2.0-flash}" \
  "${OPENCLAW_AUTH_SECRET:-}" \
  "${OPENCLAW_TELEGRAM_TOKEN:-}" \
  > /data/.openclaw/openclaw.json

chown openclaw:openclaw /data/.openclaw/openclaw.json
chmod 600 /data/.openclaw/openclaw.json

exec gosu openclaw node src/server.js
