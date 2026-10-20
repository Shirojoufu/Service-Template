# 0002: Helm over Kustomize

**Status:** Accepted

## Context

The template has to deploy the service to Kubernetes, starting with a local
kind cluster and later other environments. Teams copying the template need to
change a small set of values (image, tag, team, resources) without editing
manifests by hand, and the deploy needs to be repeatable and reversible from a
single command.

## Decision

Package the service as a Helm chart in [charts/service/](../../charts/service/):

- [values.yaml](../../charts/service/values.yaml) exposes the settings a team
  is expected to change: image, `team` label, port and resource
  requests/limits.
- `make deploy` runs `helm upgrade --install --wait`, so the same command
  covers first install and later upgrades, and only returns once the rollout
  is ready.
- [NOTES.txt](../../charts/service/templates/NOTES.txt) prints the
  port-forward command after every install, so the next step is always on
  screen.

## Alternatives considered

- **Kustomize:** built into `kubectl`, template-free, and good for layering
  environment overlays on plain YAML. But it has no release concept: no
  history, no rollback, and no single place where a service's tunable values
  are declared.
- **Plain manifests with `kubectl apply`:** the simplest option, but every
  team would copy and edit raw YAML, and changes such as a new label would
  drift between services.

## Consequences

- Helm is the most widely used Kubernetes packaging format, so the chart is
  familiar to most engineers and works with existing tooling.
- Releases are tracked, so `helm rollback` and `helm history` work out of the
  box.
- Go templating is harder to read than plain YAML, and mistakes only show up
  when rendering. `helm lint` and `helm template` should run in CI to catch
  them early.
- Environment overlays, if needed later, would be separate values files rather
  than Kustomize patches.
