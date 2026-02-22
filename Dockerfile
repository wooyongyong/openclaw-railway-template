FROM node:22-bookworm
ARG CACHE_BUST=3
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
 ca-certificates \
 curl \
 git \
 gosu \
 procps \
 python3 \
 build-essential \
 # Chromium/Playwright 의존성 라이브러리 추가
 libnss3 \
 libnspr4 \
 libatk1.0-0 \
 libatk-bridge2.0-0 \
 libcups2 \
 libdrm2 \
 libdbus-1-3 \
 libxkbcommon0 \
 libatspi2.0-0 \
 libxcomposite1 \
 libxdamage1 \
 libxfixes3 \
 libxrandr2 \
 libgbm1 \
 libpango-1.0-0 \
 libcairo2 \
 libasound2 \
 libxshmfence1 \
 xvfb \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

COPY src ./src
COPY entrypoint.sh ./entrypoint.sh

RUN useradd -m -s /bin/bash openclaw \
 && chown -R openclaw:openclaw /app \
 && mkdir -p /data && chown openclaw:openclaw /data \
 && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew

USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
 CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root
ENTRYPOINT ["./entrypoint.sh"]
