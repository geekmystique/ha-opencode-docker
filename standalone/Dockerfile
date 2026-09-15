# Global ARGs (available in FROM instructions)
ARG NODE_VERSION=24.15.0

# Standalone build: no Home Assistant Supervisor, so no HAOS base image either
# (that image exists to bundle s6-overlay + bashio for Supervisor add-ons; this
# Dockerfile installs s6-overlay itself, below, and never uses bashio at all -
# see standalone/rootfs, which reads plain environment variables instead).
FROM node:${NODE_VERSION}-trixie-slim AS node-runtime

## Build hab CLI from source (pinned release)
# Pinned to the build host's platform — Go cross-compiles via GOARCH below,
# so this stage never needs to run under emulation. hab talks to Home
# Assistant over plain REST/WebSocket with a bearer token, so it works the
# same way standalone as it does under Supervisor (see HAB_URL/HAB_TOKEN in
# rootfs/opt/ha-mcp-server/index.js) - only the token source differs.
FROM --platform=$BUILDPLATFORM golang:1.24-trixie AS hab-builder

ARG BUILD_ARCH
ARG HAB_VERSION=1.6.4
RUN git clone --depth 1 --branch "${HAB_VERSION}" https://github.com/balloob/home-assistant-build-cli.git /src
WORKDIR /src

# Cross-compile for the target architecture
RUN case "${BUILD_ARCH}" in amd64|aarch64) ;; *) echo "Unsupported BUILD_ARCH: ${BUILD_ARCH:-unset}" >&2; exit 1;; esac \
    && GOARCH=$([ "$BUILD_ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /hab .

## Stage 2: Main image
FROM debian:trixie-slim

# Build arguments
ARG BUILD_VERSION
ARG BUILD_ARCH
ARG NODE_VERSION
# No beta/stable split for the standalone image - there is only one channel.
# Overriding this is only useful for local development.
ARG ADDON_CHANNEL=standalone
ARG TTYD_VERSION=1.7.7
# Certified OpenCode runtime. This is a hard pin, never a range or a dist-tag:
# the image ships exactly one OpenCode build, it is the only one any session
# can run, and it changes only through a tested image release.
ARG OPENCODE_VERSION=1.18.29
ARG OPENCHAMBER_VERSION=1.21.0
ARG PPQ_PROXY_VERSION=0.1.0
ARG TSX_VERSION=4.20.6
ARG YQ_VERSION=v4.53.3
# https://github.com/just-containers/s6-overlay/releases - process supervisor
# used to run the terminal/OpenChamber/front-door/PPQ-proxy services. This is
# the only thing the HAOS base image provided that this Dockerfile has to
# install itself; bashio (Supervisor's config-reading helper) is not used at
# all standalone, so there is nothing else to replace.
ARG S6_OVERLAY_VERSION=3.2.0.2

# Environment for better Node.js performance
ENV NODE_ENV=production \
    npm_config_update_notifier=false \
    npm_config_fund=false

# Carried into every process in the container.
ENV ADDON_CHANNEL=${ADDON_CHANNEL}

# A failed init-opencode oneshot must take the whole container down rather
# than leave a half-configured image running - see rootfs/etc/s6-overlay/s6-rc.d/init-opencode/run.
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

RUN case "${BUILD_ARCH}" in amd64|aarch64) ;; *) echo "Unsupported BUILD_ARCH: ${BUILD_ARCH:-unset}" >&2; exit 1;; esac

# Install the exact supported Node runtime. npm is shipped with the official
# Node image.
COPY --from=node-runtime /usr/local/bin/node /usr/local/bin/node
COPY --from=node-runtime /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && ln -s node /usr/local/bin/nodejs

# Install system dependencies in a single layer
# - git: Required by OpenCode for version control operations
# - openssh-client: Provides ssh, ssh-keygen, and ssh-keyscan for Git SSH remotes
# - jq: JSON processing for helper scripts
# - curl/ca-certificates: For downloading s6-overlay/ttyd/yq and calling HA Core
# - xz-utils: To extract the s6-overlay release tarballs below
# - bzip2: Required by system tar to extract OpenChamber voice models
# - procps: Provides pgrep for health check
# - tmux: Session persistence to prevent multiple OpenCode instances
# - chromium: Headless browser for screenshot_url MCP tool (visual verification)
# - g++/make: native fallback builds for OpenChamber dependencies on all arches
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        chromium \
        curl \
        git \
        jq \
        libatomic1 \
        openssh-client \
        procps \
        python3 \
        python3-venv \
        tmux \
        xz-utils \
    && command -v ssh >/dev/null \
    && command -v ssh-keygen >/dev/null \
    && command -v ssh-keyscan >/dev/null \
    && test "$(command -v node)" = /usr/local/bin/node \
    && test "$(node --version)" = "v${NODE_VERSION}" \
    && npm --version >/dev/null \
    && rm -rf /var/lib/apt/lists/*

# Chromium path for puppeteer-core (used by screenshot MCP tool)
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# Install s6-overlay (process supervisor; provides /init as PID 1, the
# with-contenv env-injection helper, and the s6-rc.d service format this image
# uses under rootfs/etc/s6-overlay). s6-overlay's own arch naming (x86_64 /
# aarch64) already matches this project's BUILD_ARCH for the aarch64 case.
RUN S6_ARCH=$([ "$BUILD_ARCH" = "aarch64" ] && echo "aarch64" || echo "x86_64") \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" -o /tmp/s6-overlay-noarch.tar.xz \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" -o /tmp/s6-overlay-arch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz \
    && rm -f /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-arch.tar.xz \
    && test -x /init

# Install ttyd from GitHub releases (not in Debian repos)
RUN ARCH=$([ "$BUILD_ARCH" = "aarch64" ] && echo "aarch64" || echo "x86_64") \
    && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${ARCH}" -o /usr/bin/ttyd \
    && chmod +x /usr/bin/ttyd

# Install yq (mikefarah) from GitHub releases (static Go binary, not in Debian repos).
# This is the agent's YAML read/query/convert tool: unlike PyYAML or Ruby's YAML, it
# tolerates Home Assistant's custom tags (!include, !secret, !include_dir_*, !env_var,
# !input) instead of crashing on them. Release asset names use Debian arch (amd64/arm64).
# The trailing version assertion fails the build on a truncated/HTML-error download and
# guards against a colliding non-mikefarah "yq" (e.g. the PyPI jq-wrapper) shadowing it.
RUN ARCH=$([ "$BUILD_ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq \
    && yq --version | grep -q mikefarah

# Copy hab CLI binary built from source (pinned release)
# A CLI designed for AI agents to manage HA via REST/WebSocket APIs
COPY --from=hab-builder /hab /usr/local/bin/hab

# Install zigporter CLI in an isolated Python virtual environment
# A Zigbee toolkit for cascade-rename, device inspection, and mesh mapping
RUN python3 -m venv /opt/zigporter-venv \
    && /opt/zigporter-venv/bin/pip install --no-cache-dir zigporter \
    && ln -s /opt/zigporter-venv/bin/zigporter /usr/local/bin/zigporter

# Install OpenCode, OpenChamber, Prettier, and the PPQ private-mode proxy globally
# - OpenCode: AI coding agent (certified pin; see OPENCODE_VERSION above)
# - OpenChamber: browser UI for OpenCode (pinned; served at the root path here,
#   no Ingress path-rewriting is needed - see rootfs/usr/local/bin/openchamber-ingress-proxy.js)
# - Prettier: Code formatter for YAML files, configured for HA conventions
# - ppq-private-mode: local OpenAI-compatible encryption proxy for PPQ TEE models
# - tsx: pinned runtime for the PPQ package's TypeScript entrypoint
#
# The trailing assertion fails the build when the resolved OpenCode is not the
# certified one. A dist-tag or range slipping into OPENCODE_VERSION would
# otherwise publish an image whose runtime nobody tested, and the mismatch would
# surface for the first time on a user's machine. The version is also recorded
# on disk so runtime code can name the certified build without shelling out.
RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ make \
    && npm install -g --omit=dev --omit=peer --no-audit --no-fund \
        opencode-ai@${OPENCODE_VERSION} \
        @openchamber/web@${OPENCHAMBER_VERSION} \
        prettier \
        ppq-private-mode@${PPQ_PROXY_VERSION} \
        tsx@${TSX_VERSION} \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get purge -y --auto-remove g++ make \
    && INSTALLED=$(node -e "console.log(require('/usr/local/lib/node_modules/opencode-ai/package.json').version)") \
    && if [ "${INSTALLED}" != "${OPENCODE_VERSION}" ]; then \
        echo "OPENCODE_VERSION is ${OPENCODE_VERSION} but the installed runtime is ${INSTALLED}" >&2; \
        exit 1; \
    fi \
    && printf '%s\n' "${OPENCODE_VERSION}" > /usr/local/share/opencode-certified-version

# Copy package.json files first for better layer caching
# Changes to server code won't invalidate npm install cache
COPY rootfs/opt/ha-mcp-server/package*.json /opt/ha-mcp-server/
COPY rootfs/opt/ha-lsp-server/package*.json /opt/ha-lsp-server/

# Install MCP and LSP dependencies in parallel
RUN (cd /opt/ha-mcp-server && npm install --omit=dev --no-audit --no-fund) & \
    (cd /opt/ha-lsp-server && npm install --omit=dev --no-audit --no-fund) & \
    wait \
    && npm cache clean --force \
    && find /opt/ha-mcp-server/node_modules /opt/ha-lsp-server/node_modules \
        -type f \( -name '*.d.ts' -o -name '*.map' \) -delete \
    && OPENCODE_ARCH=$([ "${BUILD_ARCH}" = "aarch64" ] && echo "arm64" || echo "x64") \
    && if [ "${OPENCODE_ARCH}" = "arm64" ]; then \
        find /usr/local/lib/node_modules/opencode-ai/node_modules -mindepth 1 -maxdepth 1 -type d \
            ! -name "opencode-linux-arm64" -exec rm -rf {} +; \
    else \
        find /usr/local/lib/node_modules/opencode-ai/node_modules -mindepth 1 -maxdepth 1 -type d \
            ! -name "opencode-linux-x64" ! -name "opencode-linux-x64-baseline" -exec rm -rf {} +; \
    fi \
    && rm -rf /usr/local/lib/node_modules/ppq-private-mode/node_modules/openclaw \
    && find /usr/local/lib/node_modules -type f \( -name '*.d.ts' -o -name '*.map' -o -name '*.pdb' \) -delete \
    && test "$(opencode --version)" = "${OPENCODE_VERSION}"

# Copy root filesystem (server code, scripts, s6 services, etc.)
COPY rootfs /

# Make scripts executable and create runtime directories
RUN chmod +x /usr/local/bin/* \
    && chmod +x /etc/s6-overlay/s6-rc.d/init-opencode/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/ha-opencode/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/ha-openchamber/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/frontdoor/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/ha-opencode-server/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/ppq-private-proxy/run \
    && chmod +x /etc/profile.d/hab-esphome.sh \
    && chmod +x /etc/profile.d/zigporter-z2m.sh \
    && mkdir -p /data/.local/share/opencode /data/.config/opencode \
    && printf '%s\n' "${BUILD_VERSION:-standalone-dev}" > /usr/local/share/opencode-addon-version

# Build the custom ttyd index page (served via -I at runtime): ttyd's page is
# a single self-contained HTML file compiled into the binary, so dump it from
# a briefly-running instance and inject local browser-side fixes for clipboard,
# touch scrolling, and iframe auto-fit. The injector fails the build if the page
# could not be dumped or has an unexpected layout.
RUN set -e; \
    ttyd -p 18099 -i lo bash & \
    TTYD_PID=$!; \
    ok=0; \
    for i in $(seq 1 50); do \
        if curl -fsS -o /tmp/ttyd-index.html http://127.0.0.1:18099/; then ok=1; break; fi; \
        sleep 0.2; \
    done; \
    kill "$TTYD_PID"; \
    [ "$ok" = "1" ]; \
    python3 /opt/ttyd/inject-clipboard.py /tmp/ttyd-index.html /opt/ttyd/index.html /opt/ttyd/clipboard.js /opt/ttyd/touch-scroll.js /opt/ttyd/resize-fit.js /opt/ttyd/quit.js; \
    rm -f /tmp/ttyd-index.html

# Set working directory to the Home Assistant config directory (bind-mounted
# at runtime - see docker-compose.yml)
WORKDIR /homeassistant

# Health check - verify the front door is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -fsS --max-time 5 "http://127.0.0.1:${FRONTDOOR_PORT:-8099}/" > /dev/null || exit 1

LABEL org.opencontainers.image.title="OpenCode (standalone)" \
      org.opencontainers.image.description="AI coding agent for editing Home Assistant configuration - standalone Docker build, no Supervisor/HAOS required" \
      org.opencontainers.image.version="${BUILD_VERSION}"

ENTRYPOINT ["/init"]
