# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.15.0
FROM python:${PYTHON_VERSION}-slim

# uv binary from the official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# No .pyc files from the interpreter, unbuffered logs; uv precompiles and copies
# (cache mount is a different filesystem, so hardlinks would fail)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# Non-privileged user to run the app
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser

# Install runtime dependencies only (no pytest/httpx) from the lockfile,
# in a separate layer so code changes don't trigger a reinstall
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-dev --no-install-project

# pip ships with the base image but is never used at runtime (uv installs
# everything). Removing it drops its vendored urllib3/msgpack/setuptools,
# which otherwise show up as Trivy findings.
RUN python -m pip uninstall --yes pip

COPY app ./app

ENV PATH="/app/.venv/bin:$PATH"

USER appuser

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
