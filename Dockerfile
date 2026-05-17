# Stage 1: Build ralphex binary
FROM ghcr.io/umputun/baseimage/buildgo:latest AS build

ARG GIT_BRANCH
ARG GITHUB_SHA
ARG CI

WORKDIR /build
ADD . /build

RUN \
    if [ -z "$CI" ] ; then \
        echo "runs outside of CI"; \
        version=$(git describe --tags --always 2>/dev/null || echo "docker-$(date +%Y%m%dT%H%M%S)"); \
    else version=${GIT_BRANCH}-${GITHUB_SHA:0:7}-$(date +%Y%m%dT%H%M%S); fi && \
    echo "version=$version" && \
    go build -o /build/ralphex -ldflags "-X main.revision=${version} -s -w" ./cmd/ralphex

# Stage 2: Base runtime image
FROM ghcr.io/umputun/baseimage/app:latest

LABEL org.opencontainers.image.source="https://github.com/umputun/ralphex"
LABEL org.opencontainers.image.description="Autonomous plan execution with Claude Code"
LABEL org.opencontainers.image.licenses="MIT"

# install base tools (node.js, npm, python, essentials)
# for language-specific images, see Dockerfile-go or extend this image
RUN apk add --no-cache \
    nodejs npm \
    python3 py3-pip \
    libgcc libstdc++ ripgrep \
    fzf git jq openssh-keygen bash \
    make gcc musl-dev docker-cli && \
    sed -i 's|/home/app:/bin/sh|/home/app:/bin/bash|' /etc/passwd

# set env for claude code on alpine (use system ripgrep)
ENV USE_BUILTIN_RIPGREP=0

# mark container environment for ralphex (used to auto-disable codex sandbox)
ENV RALPHEX_DOCKER=1

# install claude code and codex globally, verify CLI commands exist
RUN npm install -g @anthropic-ai/claude-code @openai/codex && \
    command -v claude >/dev/null || { echo "error: claude CLI not found"; exit 1; } && \
    command -v codex >/dev/null || { echo "error: codex CLI not found"; exit 1; }

# install rtk (token compression proxy, amd64 only on Alpine) and opencode
# rtk upstream ships musl/amd64 and glibc/aarch64. The glibc build relies on
# FORTIFY (__memcpy_chk etc.) and fcntl64 which gcompat does not implement, so
# on aarch64 Alpine we skip rtk; init-docker.sh gates hook init on
# `command -v rtk`, so the absence is handled cleanly.
ARG RTK_VERSION=0.40.0
ARG OPENCODE_VERSION=1.14.50
RUN ARCH=$(uname -m) && \
    OC_ARCH=$(echo "$ARCH" | sed 's/x86_64/x64/;s/aarch64/arm64/') && \
    case "$ARCH" in \
        x86_64) \
            wget -qO- "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/rtk-x86_64-unknown-linux-musl.tar.gz" \
                | tar -xz -C /usr/local/bin && \
            chmod +x /usr/local/bin/rtk && \
            rtk --version ;; \
        aarch64) \
            echo "warning: rtk skipped on aarch64 (no Alpine-musl build available upstream)" ;; \
        *) echo "error: unsupported architecture: $ARCH"; exit 1 ;; \
    esac && \
    wget -qO- "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OC_ARCH}-musl.tar.gz" \
        | tar -xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/opencode && \
    opencode --version

# copy ralphex binary
COPY --from=build /build/ralphex /srv/ralphex
RUN chmod +x /srv/ralphex

# copy init script (baseimage runs /srv/init.sh before main command)
COPY scripts/internal/init-docker.sh /srv/init.sh
RUN chmod +x /srv/init.sh

# expose web dashboard port
EXPOSE 8080

WORKDIR /workspace

# baseimage runs CMD via init.sh entrypoint (handles APP_UID mapping)
CMD ["/srv/ralphex"]
