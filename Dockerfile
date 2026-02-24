FROM node:22-bookworm

# v5 - Simplified: No Homebrew, Playwright included
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates \
   curl \
    git \
     procps \
      && rm -rf /var/lib/apt/lists/*

      # Install OpenClaw globally
      RUN npm install -g openclaw@latest

      # Install Playwright Chromium with system deps
      ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
      RUN npx playwright install --with-deps chromium \
       && chmod -R 755 /opt/pw-browsers

       # Create openclaw user and directories
       RUN useradd -m -s /bin/bash openclaw \
        && mkdir -p /data && chown openclaw:openclaw /data

        WORKDIR /app
        COPY entrypoint.sh ./entrypoint.sh
        RUN chmod +x ./entrypoint.sh && chown openclaw:openclaw ./entrypoint.sh

        ENV PORT=8080
        ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
        EXPOSE 8080

        HEALTHCHECK --interval=30s --timeout=10s --start-period=30s \
         CMD curl -f http://localhost:8080/setup/healthz || exit 1

         ENTRYPOINT ["./entrypoint.sh"]
