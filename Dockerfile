FROM node:22-bookworm

# Install system dependencies (Python for Whisper, ffmpeg for audio processing)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    ffmpeg \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install OpenAI Whisper for local audio transcription
RUN pip3 install --break-system-packages openai-whisper

# Remove PEP 668 restriction so moltbot can install packages at runtime
RUN rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED && \
    pip3 config set global.break-system-packages true

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

# Patch pi-ai: fix "Cannot read properties of undefined (reading 'filter')"
# When model returns content: undefined, the code crashes
RUN for f in /app/node_modules/@mariozechner/pi-ai/dist/providers/*.js; do \
      sed -i 's/msg\.content\.filter/((msg.content) || []).filter/g' "$f"; \
      sed -i 's/msg\.content\.map/((msg.content) || []).map/g' "$f"; \
      sed -i 's/msg\.content\.some/((msg.content) || []).some/g' "$f"; \
      sed -i 's/msg\.content\.flatMap/((msg.content) || []).flatMap/g' "$f"; \
      sed -i 's/assistantMsg\.content\.filter/((assistantMsg.content) || []).filter/g' "$f"; \
      sed -i 's/assistantMsg\.content\.flatMap/((assistantMsg.content) || []).flatMap/g' "$f"; \
    done

COPY . .
RUN CLAWDBOT_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

CMD ["node", "dist/index.js"]
