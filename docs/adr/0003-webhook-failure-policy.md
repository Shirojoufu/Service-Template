# 0003: Webhook failure policy (Ignore vs Fail)

**Status:** Proposed

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

- Exclude the webhook's own `policy` namespace and `kube-system` with a
  `namespaceSelector` on the built-in `kubernetes.io/metadata.name` label, so
  the webhook can always be redeployed or fixed, and cluster components are
  never blocked.
- Scope the rule to Deployment create and update only, not every resource.
- Set a short `timeoutSeconds` so a slow webhook fails fast instead of making
  `kubectl apply` hang.
- Run more than one replica of the webhook so a single pod restart does not
  cause an outage.

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
