#!/usr/bin/env bash
# Lint each chart touched by the staged/changed files (pre-commit is fast: no ci/ matrix).
set -euo pipefail
if [ "$#" -eq 0 ]; then
  exit 0
fi
charts=$(printf '%s\n' "$@" | sed -n 's|^\(charts/[^/]*\)/.*|\1|p' | sort -u)
for chart in $charts; do
  helm lint "$chart" --strict
done
