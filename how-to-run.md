# How to Run ralphex in Docker

## Build

```bash
# base (Alpine) -- Go/Python inherit from this
make docker-build

# Go (inherits base + go toolchain)
make docker-build-go

# Python (inherits base + uv/ruff/mypy/pytest)
make docker-build-python

# Swift (separate Ubuntu-based image)
docker build -t ghcr.io/umputun/ralphex-swift:latest -f Dockerfile-swift .
```

## Run

### Via wrapper (recommended)

```bash
# base
python3 scripts/ralphex-dk.sh docs/plans/fix.md

# Go / Python / Swift -- specify image manually
python3 scripts/ralphex-dk.sh --image ghcr.io/umputun/ralphex-go:latest docs/plans/fix.md
python3 scripts/ralphex-dk.sh --image ghcr.io/umputun/ralphex-python:latest docs/plans/fix.md
python3 scripts/ralphex-dk.sh --image ghcr.io/umputun/ralphex-swift:latest docs/plans/fix.md
```

### Via docker-compose

```bash
docker compose run ralphex docs/plans/fix.md
```

### Via docker run

```bash
docker run -it --rm \
  -v $HOME/.claude:/mnt/claude:ro \
  -v $HOME/.codex:/mnt/codex:ro \
  -v $HOME/.config/ralphex:/home/app/.config/ralphex:ro \
  -v $HOME/.gitconfig:/home/app/.gitconfig:ro \
  -v $(pwd):/workspace \
  -e APP_UID=$(id -u) \
  ghcr.io/umputun/ralphex-go:latest \
  docs/plans/fix.md
```

## Verify RTK + OpenCode

```bash
docker run --rm ghcr.io/umputun/ralphex:latest rtk --version
docker run --rm ghcr.io/umputun/ralphex:latest opencode --version
```
