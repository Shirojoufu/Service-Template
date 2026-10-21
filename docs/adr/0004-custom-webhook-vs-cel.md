# 0004: Custom webhook vs built-in CEL policies vs Kyverno

**Status:** Accepted

## Context

The platform needs to enforce a few rules on every team's Deployments:

- a `team` label on the Deployment and its pod template
- CPU and memory requests and limits on every container
- images pinned to a tag or digest, never `latest`

There are three common ways to enforce rules like these at admission time:

- write a custom validating webhook
- use Kubernetes' built-in `ValidatingAdmissionPolicy`, written in CEL
- run a policy engine such as Kyverno or OPA Gatekeeper

## Decision

Implement the rules as a custom webhook in
[policy/webhook.py](../../policy/webhook.py), and implement the `team` label
rule a second time as a CEL `ValidatingAdmissionPolicy` in
[validating-admission-policy.yaml](../../charts/policy-webhook/templates/validating-admission-policy.yaml),
so the two approaches can be compared on the same rule.

For a production platform, the recommendation is to default to CEL policies
for simple, self-contained rules like these, and keep a custom webhook for
logic CEL cannot express.

## Alternatives considered

- **CEL `ValidatingAdmissionPolicy` only:** built into the API server (GA
  since Kubernetes 1.30), so there is no extra service to run, no TLS to
  manage and no network hop. Its limits are what CEL can express: no calls to
  external systems, and complex logic becomes hard to read.
- **Custom webhook only:** full Python, so any rule can be written and unit
  tested with ordinary tooling, as in
  [policy/tests/test_webhook.py](../../policy/tests/test_webhook.py). It costs
  a Deployment, a Service, a TLS certificate and an availability dependency
  (see [ADR 0003](0003-webhook-failure-policy.md)).
- **Kyverno or Gatekeeper:** mature policy engines with large libraries of
  ready-made rules, reporting and mutation. Strong for a large platform team,
  but heavy to install, operate and learn just to enforce three rules.

## Consequences

- Building the webhook shows the full admission flow end to end: an
  AdmissionReview request and response, TLS issued by cert-manager, and CA
  bundle injection.
- Having the same rule in CEL gives a direct comparison of effort, readability
  and operational cost between the two approaches.
- Two implementations of the `team` rule must be kept consistent while both
  exist. Once the comparison is done, one should be retired.
- The webhook carries the operational cost described in ADR 0003, which a
  CEL-only approach would avoid.
