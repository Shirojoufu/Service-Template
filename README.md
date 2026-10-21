# paved-road

> A ready-to-copy template for teams starting a new Python service: a FastAPI app,
> a CI pipeline with security scanning, and a Helm chart that deploys to a local
> Kubernetes cluster with one command.

[![CI](https://github.com/Shirojoufu/Service-Template/actions/workflows/ci.yml/badge.svg)](https://github.com/Shirojoufu/Service-Template/actions/workflows/ci.yml)

## Demo

`make up` from a fresh clone, trimmed to the key lines:

```
$ time make up
uv run ruff check
All checks passed!
uv run pytest -v
tests/test_main.py::test_healthz PASSED
tests/test_main.py::test_hello PASSED
docker build -t paved-road:dev .
kind create cluster --name paved-road
 ✓ Starting control-plane 🕹️
kind load docker-image paved-road:dev --name paved-road
helm upgrade --install paved-road charts/service ... --wait
STATUS: deployed
Pod is ready. Run 'kubectl port-forward svc/paved-road-service 8000:8000'

real    0m40.346s

$ curl localhost:8000/hello/graham
{"message":"Hello graham, from Service_Template"}
```

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

**Goal: first deploy in under 10 minutes.**

| Time to first deploy (`time make up`, fresh clone) | |
|---|---|
| **Cold:** nothing cached | **1m 44.8s** |
| **Warm:** images and packages already cached | **40.3s** |

The cold run started with no Docker images, no build cache, no Python
packages and no Python interpreter. Only the tools in
[Prerequisites](#prerequisites) were installed. Both runs used Docker Desktop on
Windows and were measured on 2026-10-20 (warm) and 2026-10-21 (cold).

After `make up`, forward the service and hit it:

```
kubectl port-forward svc/paved-road-service 8000:8000
curl localhost:8000/hello/graham
```

### Policy webhook (`policy/`)

An admission webhook that rejects Deployments without a `team` label, resource
requests and limits, or a pinned image tag. The `team` rule is also written as
a built-in CEL policy for comparison ([ADR 0004](docs/adr/0004-custom-webhook-vs-cel.md)).
With a cluster already up from `make up`:

```
make policy
```

This installs [cert-manager](https://cert-manager.io/) (which issues the
webhook's TLS cert), creates the `policy`, `team-a` and `team-b` namespaces
with their RBAC, deploys the webhook, and only then registers it with the
apiserver. It is a separate target from `up`, since the plain app doesn't
need it.

Try it:

```
$ kubectl create deployment bad --image=nginx:latest -n team-a
... ValidatingAdmissionPolicy 'require-team-label' ... denied request:
    metadata.labels.team is required
```

A Deployment that has the `team` label but uses `:latest` and no resources
passes the CEL policy and is rejected by the webhook instead:

```
admission webhook "deployments.policy.paved-road.dev" denied the request:
image 'nginx:latest' must not use the 'latest' tag; ...
container 'web' is missing resources.requests.cpu; ...
```

## Architecture

```mermaid
flowchart LR
    subgraph local["Local: make up"]
        dev[Developer] --> test["uv: ruff + pytest"]
        test --> build[docker build]
        build --> kind[kind cluster]
        kind --> helm[Helm chart]
        helm --> pod["Deployment + Service<br/>paved-road-service:8000"]
    end

    subgraph ci["CI: GitHub Actions"]
        pr[Pull request] --> lt[lint-and-test]
        lt --> cb["build<br/>app + webhook images"]
        cb --> scan["Trivy scan<br/>both images"]
        cb --> dt["deploy-test<br/>kind + helm install + curl"]
        scan -->|main only| ghcr[(GHCR)]
        dt -->|main only| ghcr
    end

    subgraph policy["Policy: make policy"]
        api[kube-apiserver] -->|"1. CEL policy (in-process)"| cel[require-team-label]
        api -->|"2. AdmissionReview over TLS"| wh["policy-webhook x2<br/>/validate"]
        cm[cert-manager] -->|issues TLS Secret + injects CA| wh
    end
```

- **App:** FastAPI in [app/](app/), served by uvicorn on port 8000. `/healthz` and
  `/readyz` back the chart's liveness and readiness probes.
- **Image:** built with uv from `uv.lock`, runs as a non-root user, with pip
  removed so its vendored packages don't show up in the scan.
- **CI:** every PR runs lint and tests, builds both the app and webhook images,
  and scans each with Trivy, failing on fixable HIGH/CRITICAL findings. In
  parallel, `deploy-test` installs the chart into a throwaway kind cluster and
  curls the running pod. On `main`, the app image that passed both is pushed
  to GHCR, not a rebuild. Third-party actions and the uv image are pinned by
  digest, and Dependabot keeps them current.
- **Policy:** a FastAPI webhook in [policy/](policy/) rejects Deployments
  without a `team` label, resource requests/limits, or a pinned image tag. It
  runs as two replicas under the `restricted` Pod Security profile with
  `failurePolicy: Fail`, and skips system namespaces so it can never lock
  itself out ([ADR 0003](docs/adr/0003-webhook-failure-policy.md)). Teams get
  namespace-scoped RBAC that lets them manage workloads but not read Secrets.

## Decisions

Architecture decision records live in [docs/adr/](docs/adr/):

- [0001: Why uv](docs/adr/0001-why-uv.md)
- [0002: Helm over Kustomize](docs/adr/0002-helm-over-kustomize.md)
- [0003: Webhook failure policy (Ignore vs Fail)](docs/adr/0003-webhook-failure-policy.md)
- [0004: Custom webhook vs built-in CEL policies vs Kyverno](docs/adr/0004-custom-webhook-vs-cel.md)

## What I'd do next

1. **Package the webhook as a Helm chart.** The app is a chart but the webhook
   is raw manifests applied in order by `make policy`, which is inconsistent
   with [ADR 0002](docs/adr/0002-helm-over-kustomize.md).
2. **Test the policies in CI.** `deploy-test` covers the app chart only. Running
   `make policy` in CI and asserting that a bad Deployment is rejected would
   catch a broken webhook or CEL rule before merge.
3. **Publish the webhook image.** CI builds and scans it but only pushes the
   app image to GHCR, so the webhook can only be deployed from a local build.
4. **Retire one implementation of the `team` rule.** It exists in both the
   webhook and CEL for comparison. Keeping both means two places to change it
   ([ADR 0004](docs/adr/0004-custom-webhook-vs-cel.md)).
