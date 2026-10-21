CLUSTER := paved-road
IMAGE   := paved-road
TAG     := dev
RELEASE := paved-road
SERVICE := $(RELEASE)-service
PORT    := 8000

# Recipes use POSIX shell syntax (grep, ||). When `make` is invoked from
# PowerShell or cmd.exe it otherwise falls back to cmd.exe per line, which
# doesn't have grep. Force Git Bash so recipes behave the same everywhere.
#
# Scripts are run through $(BASH) rather than plain `bash`: on Windows, make
# runs simple commands directly, and `bash` there resolves to WSL's bash,
# which can't see the Windows kubectl.
ifeq ($(OS),Windows_NT)
SHELL := C:/Program Files/Git/bin/bash.exe
.SHELLFLAGS := -c
BASH := "$(SHELL)"
else
BASH := bash
endif

POLICY_IMAGE := paved-road-policy

.PHONY: test build cluster deploy up down cert-manager policy-build policy-deploy policy policy-test

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

# Prerequisite for the policy-webhook chart, whose TLS cert is a cert-manager
# Certificate. Idempotent: safe to re-run against a cluster that already has
# it. Not part of `up`, since the plain app deploy doesn't need it.
CERT_MANAGER_VERSION := v1.21.2

cert-manager:
	@kubectl cluster-info >/dev/null 2>&1 || { echo "No cluster reachable -- run 'make cluster' first."; exit 1; }
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.yaml
	kubectl wait --for=condition=Available deployment -n cert-manager --all --timeout=120s

# Build the webhook image and load it into kind
policy-build:
	docker build $(BUILD_FLAGS) -f policy/Dockerfile -t $(POLICY_IMAGE):$(TAG) .
	kind load docker-image $(POLICY_IMAGE):$(TAG) --name $(CLUSTER)

# Install the webhook and CEL policy (charts/policy-webhook) from an image
# already in the cluster. Split from policy-build so CI can deploy the exact
# image it built and scanned.
#
# The namespace is applied separately because it carries Pod Security labels
# that `helm --create-namespace` can't set. `--wait` returns once the webhook
# pods are ready; the loop then waits for cert-manager to inject the CA, since
# until then the apiserver can't call the webhook and would reject Deployments.
policy-deploy: cert-manager
	kubectl apply -f policy/k8s/namespace.yaml -f policy/rbac/
	helm upgrade --install policy-webhook charts/policy-webhook \
		--namespace policy \
		--set image.repository=$(POLICY_IMAGE) \
		--set image.tag=$(TAG) \
		--wait --timeout 180s
	@for _ in $$(seq 1 30); do \
		kubectl get validatingwebhookconfiguration policy-webhook \
			-o jsonpath='{.webhooks[0].clientConfig.caBundle}' | grep -q . && exit 0; \
		sleep 1; \
	done; echo "caBundle was not injected by cert-manager"; exit 1
	@# The apiserver picks up new policies a moment after they're created, so
	@# wait until an unlabelled Deployment is actually rejected.
	@for _ in $$(seq 1 30); do \
		kubectl create deployment policy-probe --image=nginx:1.27.3 -n team-a \
			--dry-run=server >/dev/null 2>&1 || exit 0; \
		sleep 1; \
	done; echo "Policies were not enforced within 30s"; exit 1

# Build and deploy the webhook and CEL policy into the existing cluster
policy: policy-build policy-deploy
	@echo "Policy webhook and CEL policy are active. Check them with 'make policy-test'."

# Check the policies against the live cluster (see policy/tests/e2e.sh)
policy-test:
	$(BASH) policy/tests/e2e.sh
