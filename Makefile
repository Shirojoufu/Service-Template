CLUSTER := paved-road
IMAGE   := paved-road
TAG     := dev
RELEASE := paved-road
SERVICE := $(RELEASE)-service
PORT    := 8000

# Recipes use POSIX shell syntax (grep, ||). When `make` is invoked from
# PowerShell or cmd.exe it otherwise falls back to cmd.exe per line, which
# doesn't have grep. Force Git Bash so recipes behave the same everywhere.
ifeq ($(OS),Windows_NT)
SHELL := C:/Program Files/Git/bin/bash.exe
.SHELLFLAGS := -c
endif

POLICY_IMAGE := paved-road-policy

.PHONY: test build cluster deploy up down cert-manager policy

test:
	uv sync --locked
	uv run ruff check
	uv run pytest -v

# Extra flags for `docker build`, e.g. `make up BUILD_FLAGS="--no-cache --pull"`
BUILD_FLAGS ?=

build:
	docker build $(BUILD_FLAGS) -t $(IMAGE):$(TAG) .

# Create the kind cluster if it doesn't already exist, then load the image
cluster:
	kind get clusters | grep -qx $(CLUSTER) || kind create cluster --name $(CLUSTER)
	kind load docker-image $(IMAGE):$(TAG) --name $(CLUSTER)

deploy:
	helm upgrade --install $(RELEASE) charts/service \
		--set image.repository=$(IMAGE) \
		--set image.tag=$(TAG) \
		--wait --timeout 120s

# Everything needed to go from a fresh clone to a running pod in the
# cluster. `deploy` already waits for the rollout, so the pod is confirmed
# ready by the time this returns.
up: test build cluster deploy
	@echo "Pod is ready. Run 'kubectl port-forward svc/$(SERVICE) $(PORT):$(PORT)'"
	@echo "then visit http://localhost:$(PORT)/hello/graham"

down:
	kind delete cluster --name $(CLUSTER)

# Prerequisite for the policy webhook's TLS cert (policy/k8s/certificate.yaml
# relies on the cert-manager CRDs/controller being present in-cluster).
# Idempotent: safe to re-run against a cluster that already has it. Not part
# of `up`, since the plain app deploy doesn't need it -- run this before
# applying anything under policy/k8s/.
CERT_MANAGER_VERSION := v1.21.2

cert-manager:
	@kubectl cluster-info >/dev/null 2>&1 || { echo "No cluster reachable -- run 'make cluster' first."; exit 1; }
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.yaml
	kubectl wait --for=condition=Available deployment -n cert-manager --all --timeout=120s

# Deploy the admission webhook and the CEL policy into the existing cluster.
# Order matters: the cert must exist before the webhook pods can start, and
# the webhook must be serving (with its CA injected) before the apiserver is
# told to call it, or every Deployment would be rejected in the meantime.
policy: cert-manager
	docker build -f policy/Dockerfile -t $(POLICY_IMAGE):$(TAG) .
	kind load docker-image $(POLICY_IMAGE):$(TAG) --name $(CLUSTER)
	kubectl apply -f policy/k8s/namespace.yaml -f policy/rbac/
	kubectl apply -f policy/k8s/certificate.yaml
	kubectl wait --for=condition=Ready certificate/policy-webhook-tls -n policy --timeout=60s
	kubectl apply -f policy/k8s/deployment.yaml -f policy/k8s/service.yaml
	kubectl rollout status deployment/policy-webhook -n policy --timeout=120s
	kubectl apply -f policy/k8s/validating-webhook.yaml
	@for i in $$(seq 1 30); do \
		kubectl get validatingwebhookconfiguration policy-webhook \
			-o jsonpath='{.webhooks[0].clientConfig.caBundle}' | grep -q . && exit 0; \
		sleep 1; \
	done; echo "caBundle was not injected by cert-manager"; exit 1
	kubectl apply -f policy/k8s/validating-admission-policy.yaml
	@echo "Policy webhook and CEL policy are active."
