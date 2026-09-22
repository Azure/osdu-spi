# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical loader image, owned by the engineering system and synced to every fork
# (ADR-037, ADR-042). Packages the shared schemas that ship with the service source and
# upstream's provider-neutral loader, from the same commit as the service image:
#
#   docker run -e SCHEMA_URL=https://<host>/api/schema-service/v1 -e BEARER_TOKEN=... \
#     ghcr.io/<org>/<svc>-load:sha-<sha>
#
# Only forks whose checkout carries deployments/shared-schemas/ build it. The context is
# narrowed to the payload and the three loader files by build/load.Dockerfile.dockerignore,
# so the provider folders under deployments/scripts/ never reach the build. The loader
# resolves the payload relative to its own file, so the deployments/ layout is preserved.
FROM docker.io/library/python:3.12-slim@sha256:2f17fc044b579bab302c2e8054d3a686e2cb9a83de48e70534b94cd8ebbe06a9

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /loader

COPY deployments/scripts/requirements.txt deployments/scripts/requirements.txt
RUN pip install --no-cache-dir -r deployments/scripts/requirements.txt

COPY deployments/scripts/DeploySharedSchemas.py deployments/scripts/Utility.py deployments/scripts/
COPY deployments/shared-schemas/ deployments/shared-schemas/
COPY --chmod=0755 build/load-entrypoint.sh /usr/local/bin/load-entrypoint.sh

RUN groupadd --system loader && useradd --system --gid loader --home-dir /loader loader
USER loader

# Arguments are appended to DeploySharedSchemas.py verbatim (for example -e).
ENTRYPOINT ["/usr/local/bin/load-entrypoint.sh"]
