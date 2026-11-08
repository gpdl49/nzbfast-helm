#!/usr/bin/env bash
# Full template + kubeconform matrix (same as CI). Pre-push only — too heavy for pre-commit.
set -euo pipefail
chart=charts/nzbfast
namespace=nzbfast
for values in "$chart"/ci/*.yaml; do
  echo "kubeconform: $values"
  helm template nzbfast "$chart" --namespace "$namespace" -f "$values" \
    | kubeconform -strict -summary -ignore-missing-schemas -kubernetes-version 1.31.0
done
