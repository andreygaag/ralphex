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

# Stage 2: build rtk from source for the target platform.
# rtk upstream publishes only musl/amd64 and glibc/aarch64 binaries; the
# glibc/aarch64 build relies on FORTIFY (__memcpy_chk etc.) and fcntl64 which
# gcompat does not implement, so it cannot run on Alpine. Building from source
# in rust:1-alpine produces a native musl binary for whichever arch we build.
FROM rust:1-alpine AS rtk-build
ARG RTK_VERSION=0.40.0
RUN apk add --no-cache git musl-dev gcc make
WORKDIR /src
RUN git clone --depth 1 --branch v${RTK_VERSION} https://github.com/rtk-ai/rtk.git . && \
    cargo build --release --locked --bin rtk && \
    install -D -m 0755 target/release/rtk /out/rtk

# Stage 3: Base runtime image
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

# install rtk (built from source in rtk-build stage) and opencode
COPY --from=rtk-build /out/rtk /usr/local/bin/rtk
ARG OPENCODE_VERSION=1.14.50
RUN ARCH=$(uname -m) && \
    OC_ARCH=$(echo "$ARCH" | sed 's/x86_64/x64/;s/aarch64/arm64/') && \
    case "$ARCH" in \
        x86_64|aarch64) ;; \
        *) echo "error: unsupported architecture: $ARCH"; exit 1 ;; \
    esac && \
    wget -qO- "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OC_ARCH}-musl.tar.gz" \
        | tar -xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/opencode && \
    rtk --version && opencode --version

# install latest fya (claude print-mode PTY wrapper), usable as an optional claude_command provider
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    TAG=$(wget -qO- https://api.github.com/repos/umputun/fya/releases/latest | jq -r .tag_name) && \
    { [ -n "$TAG" ] && [ "$TAG" != "null" ]; } || { echo "error: could not resolve latest fya release"; exit 1; } && \
    wget -qO- "https://github.com/umputun/fya/releases/download/${TAG}/fya_${TAG#v}_linux_${ARCH}.tar.gz" | \
        tar -xz -C /usr/local/bin fya && \
    fya --version >/dev/null || { echo "error: fya CLI not runnable"; exit 1; }

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
