# Agent notes

Helm chart repository only (`charts/nzbfast/`). No application source or package manager.

## Local setup

Install [mise](https://mise.jdx.dev), then from the repo root:

```bash
mise install
```

Pinned tools: **helm** 3.16.4, **kubeconform** 0.6.7, **yq** 4.44.3 (same versions as CI).

Quick checks (subset of `.github/workflows/pr-validate.yaml`):

```bash
helm lint charts/nzbfast --strict
for f in charts/nzbfast/ci/*.yaml; do
  helm template nzbfast charts/nzbfast --namespace nzbfast -f "$f" >/dev/null
done
```

The workflow also runs kubeconform, a Python JSON parse check (`pyyaml` via `pip`), and a yq merge regression — see the workflow file for the full sequence.

## CI

GitHub Actions still install tools via `azure/setup-helm` and release URLs; switching to `jdx/mise-action` is a possible follow-up so versions stay in `mise.toml` only.
