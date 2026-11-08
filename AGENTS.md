# Agent notes

Helm chart repository only (`charts/nzbfast/`). No application source or package manager.

## Local setup

Install [mise](https://mise.jdx.dev) (Homebrew: `brew install mise`), then:

```bash
mise run setup
```

That runs `mise install` and `hk install --mise` so Git hooks use pinned tools.

Pinned in [`mise.toml`](mise.toml): **helm** 3.16.4, **kubeconform** 0.6.7, **yq** 4.44.3, **hk** 2.11.1, **jactionlint** 2.5.0, **yamllint** 1.38.0.

## Hooks ([`hk.pkl`](hk.pkl))

| Hook | Checks |
|------|--------|
| **pre-commit** | `helm lint` on touched charts, `yamllint` on chart YAML (not templates), `jactionlint` on workflows |
| **pre-push** | kubeconform matrix over `charts/nzbfast/ci/*` when chart files change |

Run manually: `hk check` (all checks) or `hk check --step helm-lint`.

CI still runs the full `.github/workflows/pr-validate.yaml` (JSON parse, yq merge, etc.) — not duplicated in pre-commit.

## CI follow-ups

- GitHub Actions still install tools ad hoc; `jdx/mise-action` would dedupe versions from `mise.toml`.
- `.github/jactionlint.yaml` downgrades several pedantic rules to **warn** so hooks work without a workflow redesign.
