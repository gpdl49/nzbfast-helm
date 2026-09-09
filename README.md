# nzbfast-helm

Helm chart for [nzbfast](https://github.com/nzbfast/nzbfast), the fast Usenet
downloader — packaged so its `config.json` and `settings.json` can be managed
declaratively instead of only through the dashboard.

```bash
helm install nzbfast oci://ghcr.io/gpdl49/charts/nzbfast
```

Chart documentation, values reference and the per-server field table:
**[charts/nzbfast/README.md](charts/nzbfast/README.md)**.

## What is interesting here

nzbfast is a UI-configured application. It persists what you set into two
files in `/config`, and rewrites both at runtime with an atomic
`write`+`rename` — so neither can be a read-only `subPath` mount, which is the
usual trick for putting an app's config file in Git.

This chart takes a different route: it renders the files into Secrets, and an
init container places them onto the `/config` volume before the daemon starts.
That keeps the files writable, so the dashboard keeps working, while letting
Helm own whichever keys you choose.

The `settings.json` default is **merge**, not overwrite, because that file also
holds generated runtime state — the API key nzbfast made for itself, indexer
bookkeeping, history counters. Overwriting it wholesale on every restart
throws all of that away. Merge makes the keys you set declarative and leaves
everything else alone.

## Repository layout

```
charts/nzbfast/          the chart
  ci/                    values files exercised by CI, one per mode
.github/workflows/
  pr-validate.yaml       lint + template + schema check on PRs
  publish.yaml           package + push to GHCR on a chart-v* tag
```

## Releasing

Bump `version` in `charts/nzbfast/Chart.yaml`, then:

```bash
git tag chart-v0.1.0
git push origin chart-v0.1.0
```

The workflow packages the chart and pushes it to
`oci://ghcr.io/gpdl49/charts/nzbfast`. The tag version and the `Chart.yaml`
version must match; the workflow fails if they do not.

## Licence

MIT — see [LICENSE](LICENSE). nzbfast itself is GPL-3.0 and is not vendored
here; this repository only packages it.
