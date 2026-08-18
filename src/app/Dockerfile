# This Dockerfile is built by Pants (`pants package src/app:docker`, wired up
# as `make build`), never by hand with a bare `docker build .` -- Pants
# packages `src/app:app` (the pex_binary below) into a PEX and copies it into
# this build's context as `src.app/app.pex` (the dotted, repo-root-relative
# address of the pex_binary target) before invoking `docker build`. See
# `docs/DESIGN-NOTES.md` for why this project builds this way.
FROM python:3.11-slim AS build

COPY src.app/app.pex /app.pex
# Converts the self-contained PEX into a plain venv layout at build time so
# the final image starts faster (no PEX zip-bootstrap cost on every
# container start).
RUN PEX_TOOLS=1 python3.11 /app.pex venv --compile --scope=all /opt/app/

FROM python:3.11-slim

RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin appuser
COPY --from=build /opt/app /opt/app
WORKDIR /opt/app

ARG BUILD_VERSION=dev
ENV BUILD_VERSION=${BUILD_VERSION} \
    PYTHONUNBUFFERED=1

USER appuser
EXPOSE 8080

# The venv `pex` entrypoint script already knows to run
# `gunicorn app.main:app -c python:app.gunicorn_conf` -- that command line is
# baked in by the pex_binary target's own `args`, not repeated here.
ENTRYPOINT ["/opt/app/pex"]
