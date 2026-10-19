# paved-road

> One line: what this is and who it is for.

[![CI](https://github.com/Shirojoufu/Service-Template/actions/workflows/ci.yml/badge.svg)](https://github.com/Shirojoufu/Service-Template/actions/workflows/ci.yml)

## Demo
<!-- GIF, screenshot or terminal recording -->

## Quick start

```
make up      # test, build, load into a local kind cluster, and deploy via Helm
make down    # tear down the kind cluster
```

**Time to first deploy: 44.3s** (`time make up`, fresh clone, warm Docker/base-image
cache — see note below). Measured on 2026-10-20 with Docker Desktop, kind v0.30.0
and Helm already installed.

After `make up`, forward the service and hit it:

```
kubectl port-forward svc/hello-service 8000:8000
curl localhost:8000/hello/graham
```

> This number assumes the `python:3.15-slim`, `ghcr.io/astral-sh/uv` and
> `kindest/node` images are already pulled. A genuinely cold machine (nothing
> cached, pulling everything from scratch) will take noticeably longer,
> dominated by those image pulls rather than by the build/test/deploy steps
> themselves.

## Architecture
<!-- Simple diagram of the parts and how they talk -->

## Decisions
<!-- Link each record in docs/adr/ -->

## What I'd do next
<!-- 3-4 honest improvements -->
