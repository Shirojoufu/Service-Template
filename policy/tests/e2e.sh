#!/usr/bin/env bash
# End-to-end check that the admission policies are enforced by a live cluster.
# Uses --dry-run=server: the apiserver runs the full admission chain (CEL
# policy and webhook) but nothing is created, so this leaves no clutter.
#
#   make policy-test
set -euo pipefail

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "No cluster reachable -- run 'make up' first."
  exit 1
fi
if ! kubectl get validatingwebhookconfiguration policy-webhook >/dev/null 2>&1 ||
   ! kubectl get namespace team-a >/dev/null 2>&1; then
  echo "Policies aren't installed on this cluster -- run 'make policy' first."
  exit 1
fi

failures=0

deployment() {
  # deployment <name> <namespace> <extra-labels> <image> <with-resources:yes|no>
  # <extra-labels> is a JSON fragment such as '"team": "team-a"', or ''.
  local labels="{${3}}" template_labels="{\"app\": \"$1\"${3:+, $3}}"
  local resources=""
  if [[ $5 == yes ]]; then
    resources='"resources": {"requests": {"cpu": "10m", "memory": "16Mi"},
                             "limits":   {"cpu": "50m", "memory": "32Mi"}},'
  fi
  cat <<EOF
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {"name": "$1", "namespace": "$2", "labels": $labels},
  "spec": {
    "selector": {"matchLabels": {"app": "$1"}},
    "template": {
      "metadata": {"labels": $template_labels},
      "spec": {"containers": [{"name": "web", $resources "image": "$4"}]}
    }
  }
}
EOF
}

expect_denied() {
  # expect_denied <description> <expected message> <manifest>
  local out
  if out=$(kubectl apply --dry-run=server -f - <<<"$3" 2>&1); then
    echo "FAIL: $1 was admitted, expected rejection"
    failures=$((failures + 1))
  elif grep -qF "$2" <<<"$out"; then
    echo "PASS: $1 rejected: $2"
  else
    echo "FAIL: $1 rejected, but without '$2':"
    echo "$out"
    failures=$((failures + 1))
  fi
}

expect_allowed() {
  # expect_allowed <description> <manifest>
  local out
  if out=$(kubectl apply --dry-run=server -f - <<<"$2" 2>&1); then
    echo "PASS: $1 admitted"
  else
    echo "FAIL: $1 was rejected, expected admission:"
    echo "$out"
    failures=$((failures + 1))
  fi
}

team='"team": "team-a"'

expect_denied "no team label (CEL policy)" \
  "metadata.labels.team is required" \
  "$(deployment no-team team-a '' nginx:1.27.3 yes)"

expect_denied ":latest image (webhook)" \
  "must not use the 'latest' tag" \
  "$(deployment latest team-a "$team" nginx:latest yes)"

expect_denied "untagged image (webhook)" \
  "has no tag" \
  "$(deployment untagged team-a "$team" nginx yes)"

expect_denied "no resource requests/limits (webhook)" \
  "missing resources.limits.memory" \
  "$(deployment no-resources team-a "$team" nginx:1.27.3 no)"

expect_allowed "compliant Deployment" \
  "$(deployment good team-a "$team" nginx:1.27.3 yes)"

expect_allowed "non-compliant Deployment in an excluded namespace (kube-system)" \
  "$(deployment excluded kube-system '' nginx:latest no)"

if ((failures > 0)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All policy checks passed"
