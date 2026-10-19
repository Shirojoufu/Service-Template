CLUSTER := paved-road
IMAGE   := paved-road
TAG     := dev
RELEASE := hello
SERVICE := $(RELEASE)-service
PORT    := 8000

.PHONY: test build cluster deploy up down

test:
	uv sync --locked
	uv run ruff check
	uv run pytest -v

build:
	docker build -t $(IMAGE):$(TAG) .

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
