# ============================================================
# Stage 1: 编译 better-sqlite3 原生模块（针对 Electron ABI）
# ============================================================
FROM node:22-slim AS native-builder

RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

RUN npm config set registry https://registry.npmmirror.com && \
    npm install -g bun

WORKDIR /app

# 只 COPY 依赖相关文件 → 最大化层缓存命中率
COPY package.json bun.lock ./
COPY patches ./patches/
COPY scripts ./scripts/

# 1. 安装生产依赖（跳过所有脚本）
# 2. 用 electron-rebuild 针对 Electron 的 Node ABI 重编译 better-sqlite3
RUN CI=1 ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    bun install --production --omit=optional --no-save --ignore-scripts && \
    ELECTRON_VER=$(node -e "console.log(require('./package.json').devDependencies.electron.replace('^',''))") && \
    npx --yes @electron/rebuild -v "$ELECTRON_VER" -m . -o better-sqlite3

# ============================================================
# Stage 2: 运行时镜像（不含编译工具链）
# ============================================================
FROM node:22-slim AS runtime

RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && apt-get install -y --no-install-recommends \
    # Electron 运行依赖
    libgtk-3-0 libgbm1 libnss3 libnspr4 \
    libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 \
    libpango-1.0-0 libcairo2 libasound2 libxss1 libxtst6 \
    # 虚拟显示
    xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN npm config set registry https://registry.npmmirror.com && \
    npm install -g opencode-ai@latest

WORKDIR /app

# 从 native-builder 拷贝已编译好的 node_modules（含 Electron ABI 的 .node）
COPY --from=native-builder /app/node_modules ./node_modules

# 安装 electron（全局，利用缓存层）
COPY package.json ./
RUN npm install -g electron@$(node -e "console.log(require('./package.json').devDependencies.electron.replace('^',''))")

# 拷贝构建产物（变动最频繁的层放最后）
COPY out ./out
COPY dist-server ./dist-server
COPY src/process/resources ./src/process/resources
COPY docker-entry.sh /docker-entry.sh
RUN chmod +x /docker-entry.sh

ENV NODE_ENV=production
ENV DISPLAY=:99
ENV DATA_DIR=/data
ENV AIONUI_ALLOW_REMOTE=true

VOLUME ["/data"]
EXPOSE 25808

CMD ["/docker-entry.sh"]
