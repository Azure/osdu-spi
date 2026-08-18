# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical service container image for OSDU SPI Python (uv) services.
# Owned by the engineering system and synced to every fork (ADR-037 ownership model);
# services do not supply their own CI Dockerfile.
#
# Unlike the Java image, which copies a prebuilt JAR, the Python image is built from
# source plus the committed lockfile: `uv sync --frozen` installs exactly the dependency
# set the build job tested. No dependency is re-resolved at image build time.
#
# Base: Microsoft Azure Linux Python 3.12 (MCR) — multi-arch (amd64+arm64) and
# digest-pinned for reproducibility. The docker Dependabot ecosystem (template only)
# bumps these digests as a PR and template-sync propagates them to every fork.
# MCR does not publish an azurelinux/base/python:3.13 tag, so 3.13 remains a CI
# compatibility matrix leg only, never the runtime.
#
# Package index credentials MUST be supplied as a BuildKit secret:
#
#   docker build --secret id=netrc,src=$HOME/.netrc -f build/python/Dockerfile .
#
# Never pass a credential-bearing index URL as a build argument (--build-arg
# PIP_INDEX_URL=...): build arguments are recorded in image history and leak.
# Index *policy* (which index serves which distribution) belongs in the
# repository-owned uv.toml / pyproject.toml, not in this Dockerfile.

# uv itself is pinned by digest rather than installed from a network script.
FROM ghcr.io/astral-sh/uv:0.12.5@sha256:e85be844203885286c60ffad8a858d48afb6c5a5c237ca0e67f12e74b8f174b1 AS uv

FROM mcr.microsoft.com/azurelinux/base/python:3.12@sha256:722b6224c23b3f21f5268e2073f80c0f396bc626e3193b6dbf66e40d89478f03 AS builder

# Comma-separated optional-dependency extras installed into the runtime environment
# (for example "az" for the Azure provider). Each entry is validated below; the empty
# default installs the base runtime dependency set only.
ARG RUNTIME_EXTRAS=""

ENV UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON=python3 \
    UV_PYTHON_DOWNLOADS=never \
    UV_NO_PROGRESS=1

COPY --from=uv /uv /usr/local/bin/uv

WORKDIR /src

# Dependency layer: manifest + lockfile only, so dependency installation is cached
# independently of application source changes.
COPY pyproject.toml uv.lock ./
RUN --mount=type=secret,id=netrc,target=/run/secrets/netrc,mode=0400 \
    set -eu; \
    EXTRA_ARGS=""; \
    IFS=','; \
    for extra in ${RUNTIME_EXTRAS}; do \
      [ -n "$extra" ] || continue; \
      case "$extra" in \
        *[!A-Za-z0-9._-]*) echo "Invalid RUNTIME_EXTRAS entry: $extra" >&2; exit 1 ;; \
      esac; \
      EXTRA_ARGS="$EXTRA_ARGS --extra $extra"; \
    done; \
    unset IFS; \
    NETRC=/run/secrets/netrc uv sync --frozen --no-dev --no-install-project $EXTRA_ARGS

# Application layer: the project itself, installed non-editable so the runtime image
# needs no source tree. Package data must be declared in pyproject.toml — files that
# are not part of the distribution are not present at runtime.
COPY . /src
RUN --mount=type=secret,id=netrc,target=/run/secrets/netrc,mode=0400 \
    set -eu; \
    EXTRA_ARGS=""; \
    IFS=','; \
    for extra in ${RUNTIME_EXTRAS}; do \
      [ -n "$extra" ] || continue; \
      case "$extra" in \
        *[!A-Za-z0-9._-]*) echo "Invalid RUNTIME_EXTRAS entry: $extra" >&2; exit 1 ;; \
      esac; \
      EXTRA_ARGS="$EXTRA_ARGS --extra $extra"; \
    done; \
    unset IFS; \
    NETRC=/run/secrets/netrc uv sync --frozen --no-dev --no-editable $EXTRA_ARGS


FROM mcr.microsoft.com/azurelinux/base/python:3.12@sha256:722b6224c23b3f21f5268e2073f80c0f396bc626e3193b6dbf66e40d89478f03 AS runtime

# ASGI application target, e.g. "wdmsworker.app:app". Required: the Stack chart does not
# override the container command, so the uvicorn invocation is baked into the image.
ARG APP_MODULE=""
ARG APP_PORT="8080"
ARG APP_HOST="0.0.0.0"
ARG UVICORN_WORKERS="1"
ARG UVICORN_LOG_LEVEL="info"
# Optional ASGI root path (deployed API prefix) and container-local health path.
ARG UVICORN_ROOT_PATH=""
ARG HEALTH_PATH=""
# OCI provenance; the docker-build action supplies the repository source label.
ARG IMAGE_SOURCE=""
ARG IMAGE_REVISION=""
ARG IMAGE_VERSION=""

LABEL org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.vendor="Microsoft Azure Energy" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.base.name="mcr.microsoft.com/azurelinux/base/python:3.12" \
      org.opencontainers.image.base.digest="sha256:722b6224c23b3f21f5268e2073f80c0f396bc626e3193b6dbf66e40d89478f03"

ENV SPI_APP_MODULE="${APP_MODULE}" \
    SPI_APP_HOST="${APP_HOST}" \
    SPI_APP_PORT="${APP_PORT}" \
    SPI_UVICORN_WORKERS="${UVICORN_WORKERS}" \
    SPI_UVICORN_LOG_LEVEL="${UVICORN_LOG_LEVEL}" \
    SPI_UVICORN_ROOT_PATH="${UVICORN_ROOT_PATH}" \
    SPI_HEALTH_PATH="${HEALTH_PATH}" \
    PATH="/app/.venv/bin:${PATH}" \
    HOME="/app" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# The Stack chart runs services as runAsUser 1000. The virtual environment is copied
# with that ownership and USER is numeric, so the image works without an /etc/passwd
# entry and needs no useradd in the base layer.
COPY --from=builder --chown=1000:1000 /app/.venv /app/.venv
COPY --chmod=0755 build/python/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

USER 1000:1000
WORKDIR /app
EXPOSE ${APP_PORT}

# Kubernetes uses the chart's probes; this HEALTHCHECK only helps local/compose runs and
# is a no-op when HEALTH_PATH is not configured.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/usr/local/bin/docker-entrypoint.sh", "healthcheck"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
