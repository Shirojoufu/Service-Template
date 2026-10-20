# paved-road

> One line: what this is and who it is for.

[![CI](https://github.com/Shirojoufu/Service-Template/actions/workflows/ci.yml/badge.svg)](https://github.com/Shirojoufu/Service-Template/actions/workflows/ci.yml)

## Demo
<!-- GIF, screenshot or terminal recording -->

## Prerequisites

Install these before running anything below. Versions are what this repo was
last tested with (2026-10-20) — newer patch/minor versions should be fine.

| Tool | Version tested | Windows (choco) | Linux (apt) | macOS (brew) |
|---|---|---|---|---|
| [Docker](https://docs.docker.com/get-docker/) | 29.9.1 | `choco install docker-desktop` | `sudo apt-get install docker.io` | `brew install --cask docker` |
| [make](https://www.gnu.org/software/make/) | GNU Make 4.4.1 | `choco install make` | `sudo apt-get install make` | `brew install make` |
| [kind](https://kind.sigs.k8s.io/) | 0.30.0 | `choco install kind` | [download the binary](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | `brew install kind` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.37.1 | `choco install kubernetes-cli` | [add the Kubernetes apt repo](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) | `brew install kubectl` |
| [Helm](https://helm.sh/) | v4.1.4 | `choco install kubernetes-helm` | [official install script](https://helm.sh/docs/intro/install/) | `brew install helm` |
| [uv](https://docs.astral.sh/uv/) | 0.13.1 | `choco install uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` | `brew install uv` |

> On Windows, `choco install kind` has been seen pulling in `docker-desktop`
> as an unwanted dependency and failing on a lock file; if that happens,
> grab the [kind binary](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
> directly. If `choco install make` fails the same way, `winget install
> ezwinports.make` is a reliable fallback.

## Quick start

```
make up      # test, build, load into a local kind cluster, and deploy via Helm
make down    # tear down the kind cluster
```

**Time to first deploy: 40.3s** (`time make up`, fresh clone, warm Docker/base-image
cache — see note below). Measured on 2026-10-20 with Docker Desktop, kind v0.30.0
and Helm already installed.

After `make up`, forward the service and hit it:

```
kubectl port-forward svc/paved-road-service 8000:8000
curl localhost:8000/hello/graham
```

> This number assumes the `python:3.15-slim`, `ghcr.io/astral-sh/uv` and
> `kindest/node` images are already pulled. A genuinely cold machine (nothing
> cached, pulling everything from scratch) will take noticeably longer,
> dominated by those image pulls rather than by the build/test/deploy steps
> themselves.

### Policy webhook (`policy/`)

The admission webhook's TLS cert is issued by [cert-manager](https://cert-manager.io/),
not managed by hand. Install it once per cluster before applying anything under
`policy/k8s/`:

```
make cert-manager
```

This is a separate, idempotent target (not part of `up`), since the plain app
deploy above doesn't need it.

## Architecture
<!-- Simple diagram of the parts and how they talk -->

## Decisions
<!-- Link each record in docs/adr/ -->

## What I'd do next
<!-- 3-4 honest improvements -->
