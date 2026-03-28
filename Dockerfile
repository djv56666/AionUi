# ============================================================
# Stage 1: 安装生产依赖（native 模块针对 Node.js ABI 编译）
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

# 安装生产依赖（native 模块自动针对 Node.js ABI 编译）
RUN CI=1 bun install --production --omit=optional --no-save --ignore-scripts && \
    npm rebuild better-sqlite3

# 清理非运行时文件，减小镜像体积
RUN cd node_modules && \
    rm -rf \
      electron-log electron-updater electron-squirrel-startup \
      @sentry @sentry-internal && \
    find . -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.md' \) -delete && \
    find . -type d \( -name 'test' -o -name 'tests' -o -name '__tests__' \
      -o -name 'docs' -o -name 'doc' -o -name 'example' -o -name 'examples' \
      -o -name 'benchmark' -o -name '.github' -o -name 'spec' -o -name 'specs' \) \
      -exec rm -rf {} + 2>/dev/null; true

# ============================================================
# Stage 2: 精简运行时镜像（无 Electron、无 Xvfb、无 GTK）
# ============================================================
FROM node:22-slim AS runtime

WORKDIR /app

# 从 native-builder 拷贝已编译好的 node_modules（Node.js ABI）
COPY --from=native-builder /app/node_modules ./node_modules

# 安装 opencode-ai 作为执行层
RUN npm config set registry https://registry.npmmirror.com && \
    npm install -g opencode-ai@latest

# 拷贝构建产物（变动最频繁的层放最后）
COPY out ./out
COPY dist-server ./dist-server
COPY src/process/resources ./src/process/resources
COPY docker-entry.sh /docker-entry.sh
RUN chmod +x /docker-entry.sh

ENV NODE_ENV=production
ENV DATA_DIR=/data
ENV PORT=3000
ENV ALLOW_REMOTE=true

VOLUME ["/data"]
EXPOSE 3000

CMD ["/docker-entry.sh"]
