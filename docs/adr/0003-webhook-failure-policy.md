# 0003: Webhook failure policy (Ignore vs Fail)

**Status:** Accepted

## Context

The policy webhook in [policy/](../../policy/) rejects Deployments that lack a
`team` label, resource requests and limits, or a pinned image. The
`ValidatingWebhookConfiguration` must set a `failurePolicy` that tells the
kube-apiserver what to do when the webhook cannot be reached or times out:

- `Ignore` admits the request as if the webhook had allowed it.
- `Fail` rejects the request.

This is a trade-off between enforcement and availability. A policy that is
skipped whenever the webhook is down is not really enforced. A webhook that
blocks every Deployment when it is down can stop the whole cluster from
changing.

## Decision

Use `failurePolicy: Fail`, and limit the damage an outage can cause:

- Exclude namespaces by name with a `namespaceSelector` on the built-in
  `kubernetes.io/metadata.name` label:
  - `policy`, so the webhook can always be redeployed or fixed
  - `kube-system`, so cluster components are never blocked
  - `cert-manager`, which issues the webhook's own certificate
  - `local-path-storage`, kind's built-in storage provisioner
- Scope the rule to Deployment create and update only, not every resource.
- Set `timeoutSeconds: 5` so a slow webhook fails fast instead of making
  `kubectl apply` hang.
- Run two replicas of the webhook so a single pod restart does not cause an
  outage.

These are implemented in
[policy/k8s/validating-webhook.yaml](../../policy/k8s/validating-webhook.yaml)
and [policy/k8s/deployment.yaml](../../policy/k8s/deployment.yaml).

## Alternatives considered

- **`Ignore`:** keeps the cluster available when the webhook is down, but
  turns the policy into best-effort. Non-compliant workloads get in silently
  during any outage, which is when nobody is watching.
- **`Fail` with no exclusions:** the strictest option, but the webhook would
  then block its own redeploy. A broken webhook could only be fixed by
  deleting the `ValidatingWebhookConfiguration` by hand.

## Consequences

- The policy is actually enforced: a Deployment cannot bypass it because the
  webhook happened to be unavailable.
- Webhook availability now matters. If it is down, teams cannot deploy to
  their namespaces until it is restored, so it needs monitoring and enough
  replicas.
- The break-glass procedure is to delete the `ValidatingWebhookConfiguration`.
  This should be documented, and restricted to cluster admins.
