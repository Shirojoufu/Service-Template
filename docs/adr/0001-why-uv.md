# 0001: Why uv

**Status:** Accepted

## Context

The template needs one tool to manage Python versions, virtual environments
and dependencies, and to do it the same way on a laptop, in CI and in the
Docker build. Every service copied from the template inherits this choice, so
it has to be fast, reproducible and simple enough that a new team doesn't need
to learn several tools to get started.

## Decision

Use [uv](https://docs.astral.sh/uv/) for everything Python-related:

- `pyproject.toml` declares dependencies, with dev tools (pytest, ruff, httpx2)
  in a `dev` dependency group.
- `uv.lock` pins every package version and hash, and is committed.
- CI and the Dockerfile both install with `uv sync --locked`, which fails if
  the lockfile and `pyproject.toml` have drifted apart.
- The runtime image installs with `--no-dev`, so test and lint tools never
  ship to production.

## Alternatives considered

- **pip + requirements.txt:** universally understood, but has no built-in
  lockfile with hashes and no Python version management. Keeping dev and
  runtime dependencies apart needs several files by convention.
- **Poetry:** mature lockfile and dependency groups, but noticeably slower to
  resolve and install, and it does not manage Python versions itself.
- **pip-tools:** produces good lockfiles on top of pip, but is one more tool
  alongside pip, venv and pyenv rather than a replacement for them.

## Consequences

- Installs are fast enough that a cold `uv sync` is a small part of
  time-to-first-deploy.
- One lockfile drives local, CI and the image, so "works on my machine"
  dependency drift is caught by `--locked` instead of in production.
- Contributors need uv installed (see the README prerequisites). It is newer
  than pip, so some engineers will be meeting it for the first time.
- The Docker build copies uv in from `ghcr.io/astral-sh/uv`, which adds an
  external image to the supply chain that should be pinned.
