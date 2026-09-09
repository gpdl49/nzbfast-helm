# nzbfast Helm chart

Runs [nzbfast](https://github.com/nzbfast/nzbfast) on Kubernetes and makes its
two on-disk config files declarative.

```bash
helm install nzbfast oci://ghcr.io/gpdl49/charts/nzbfast
```

## Why this chart exists

nzbfast is configured through its dashboard. It persists what you set into
`/config`, and by default nothing outside the container knows what is in there.
This chart puts those files under Helm, without breaking the dashboard.

nzbfast keeps two files:

| File | Holds | Written by |
|---|---|---|
| `config.json` | Usenet servers and credentials, optional `tmdb_key` | you, or the Servers screen |
| `settings.json` | every Settings-screen value **and** generated runtime state — the API key, indexer bookkeeping, history counters | nzbfast, constantly |

Both are read-modify-written by nzbfast at runtime with an atomic
`write`+`rename`, so **neither can be a read-only `subPath` mount** — the
rename needs a writable directory. Instead an init container places the
rendered files onto the `/config` volume before the daemon starts.

## Modes

### `config.mode` — servers

| Mode | Behaviour |
|---|---|
| `enforce` *(default)* | Rewrite `config.json` from values on every pod start. Git wins; UI server edits revert on restart. |
| `seed` | Write it only if absent. The UI owns servers after first start. |
| `disabled` | Never touch it. |

### `settings.mode`

| Mode | Behaviour |
|---|---|
| `merge` *(default)* | Deep-merge `settings.values` over the file on disk each start. Your keys are declarative; **everything else survives**, including the API key nzbfast generated for itself. Needs the `settings.mergeTool` image. |
| `enforce` | Replace the file wholesale. **Destructive** — discards the generated API key, indexer coverage bookkeeping and history counters on every restart. Only for a complete, known-good file. |
| `seed` | Write only if absent. |
| `disabled` | Never touch it. |

`merge` is the default precisely because `enforce` is destructive for this
app. In merge, maps merge recursively and **arrays are replaced**, so setting
a list key (`custom_categories`, `smart_folders`, `arr_instances`) in Helm
gives Helm ownership of that whole list.

> `disabled` must be quoted as a mode name only if you write it as `off` —
> which is why this chart does not use `off`. YAML would turn it into `false`.

## Servers

`level` is the tiering knob and it is what makes multiple providers worth
having: level `0` is the primary pool, higher levels are only asked for
articles the pool could not supply. Put metered block accounts at a higher
level than unlimited ones so they are only billed for genuine fills.

```yaml
config:
  mode: enforce
  servers:
    - host: news.newshosting.com
      username: someone
      password: secret
      connections: 30
      level: 0
      retention_days: 5900
    - host: news.eweka.nl
      username: someone
      password: secret
      connections: 20
      level: 0
      group: omicron          # same backbone → not raced against each other
    - host: news.blocknews.net
      username: someone
      password: secret
      connections: 10
      level: 2
      block_account: true
      block_bytes: 536870912000
```

Full per-server field list:

| Field | Default | Meaning |
|---|---|---|
| `host` | *required* | NNTP hostname |
| `port` | `563` | 563 for TLS, 119 plain |
| `tls` | `true` | |
| `username` / `password` | — | omit for accounts needing no auth |
| `connections` | upstream default | max simultaneous connections |
| `level` | `0` | 0 = primary pool; higher = fill-only tiers |
| `enabled` | `true` | `false` parks the account without deleting it |
| `retention_days` | `0` | provider retention |
| `block_account` | `false` | metered/block account |
| `block_bytes` | — | remaining block bytes, for the dashboard gauge |
| `group` | — | backbone grouping; same group is not raced |
| `pin_connections` | `false` | stop the autotuner reducing `connections` |
| `warm_pool` | `false` | keep connections warm between jobs |
| `warm_reserve` | — | connections held warm |
| `address_family` | `auto` | `auto` \| `ipv4` \| `ipv6` |
| `tls_hostname` | — | override SNI/cert hostname |
| `bind_ip` | — | source address to bind |
| `socks5` | — | SOCKS5 proxy |
| `rcvbuf` | — | socket receive buffer |
| `idle_keep` / `idle_release_secs` | — | idle connection retention |
| `max_source_ips` | — | cap distinct source IPs |

### Keeping credentials out of values

Three options, in increasing order of hygiene:

1. **Whole file from a Secret** you manage with SOPS / External Secrets /
   sealed-secrets:

   ```yaml
   config:
     existingSecret: nzbfast-config
     existingSecretKey: config.json
   ```

2. **Flux `valuesFrom`**, injecting one field:

   ```yaml
   valuesFrom:
     - kind: Secret
       name: usenet-credentials
       valuesKey: newshosting_password
       targetPath: config.servers[0].password
   ```

3. Inline in values — only when the values themselves are encrypted.

## settings.json

Any key nzbfast persists can go in `settings.values`. The chart does not
validate names: an unknown key is written and nzbfast ignores it, so check
spelling against the Settings screen.

```yaml
settings:
  mode: merge
  values:
    speedlimit: 0                 # KB/s, 0 = unlimited
    min_free: 10737418240         # pause below 10 GiB free
    auto_connections: true        # let nzbfast tune connection counts
    verify_mode: full
    auto_rename: true
    history_keep_count: 500
    watch_interval_secs: 30
    metrics_open: true            # unauthenticated GET /metrics
    categories: "tv, movies, books"
```

Commonly-set keys, by area:

| Area | Keys |
|---|---|
| Speed / limits | `speedlimit`, `quota`, `quota_period`, `line_speed`, `auto_speed`, `slow_storage_pause` |
| Connections | `auto_connections`, `conntune`, `live_tune`, `adaptive_timeouts`, `server_outage_mins` |
| Disk | `min_free`, `out_dir`, `out_umask`, `move_completed`, `move_pace`, `write_through` |
| Verify / repair | `verify_mode`, `fast_verify`, `fast_par`, `par_cleanup`, `heal_auto`, `unpack_eat_volumes` |
| Naming | `auto_rename`, `rename_resolution`, `rename_vcodec`, `rename_acodec`, `rename_source`, `rename_group`, `rename_junk`, `smart_folders` |
| History | `history_keep_count`, `history_keep_secs`, `history_rows` |
| Watch folder | `watch`, `watch_interval_secs`, `watch_recursive`, `watch_keep_nzb`, `watch_move_rejected` |
| Categories | `categories`, `custom_categories`, `cat_meta` |
| Indexer | `index_enabled`, `index_groups`, `index_interval_secs`, `index_retention`, `index_max_bytes` |
| Scripts | `script`, `script_timeout_secs`, `script_confined`, `pre_queue_script` |
| Notifications | `notify_targets`, `email_to`, `email_from`, `on_failure` |
| Security | `apikey`, `cors_origin`, `metrics_open`, `tls_cert`, `tls_key` |
| *arr integration | `arr_instances`, `arr_giveup_threshold` |

Upstream's full list is the settings catalogue in
[`crates/nzbfast-daemon/src/settings.rs`](https://github.com/nzbfast/nzbfast/blob/main/crates/nzbfast-daemon/src/settings.rs).

## API key

Sonarr/Radarr authenticate with it. Leave `apiKey` unset and nzbfast generates
one into `/config/apikey` — which means it is not in Git and does not survive
a PVC wipe. Better:

```yaml
apiKey:
  existingSecret: nzbfast-apikey
  existingSecretKey: apikey
```

`apiKey.open: true` sets `NZBFAST_OPEN=1` and runs with no key at all.

## Identity and permissions

The upstream entrypoint starts as **root**, chowns `/config`, `/downloads`,
`/watch` and `/incomplete` to `puid:pgid`, then drops with `gosu`. That needs
`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID` — the chart's default
`securityContext` drops `ALL` and adds exactly those five.

`rootless: true` skips it: the pod runs as `puid:pgid` throughout, no
capabilities are added, and you must make the volumes writable by that uid
yourself (`podSecurityContext.fsGroup` normally does it).

## Storage

| Value | Mount | Notes |
|---|---|---|
| `persistence.config` | `/config` | **This is the install.** settings.json, config.json, apikey, index DB, queue spool. |
| `persistence.downloads` | `/downloads` | Mount at the *same path* your *arr apps see, or every import copies instead of hardlinking. |
| `persistence.watch` | `/watch` | Drop `.nzb` files here. |
| `persistence.incomplete` | `/incomplete` | The image creates and chowns this path; a volume here gives in-flight data its own storage. The path is fixed — no env var relocates it. |

PVCs the chart creates carry `helm.sh/resource-policy: keep`, so
`helm uninstall` does not delete your downloads.

## Download paths

nzbfast separates the working directory from the final destination, which maps
onto NZBGet's `InterDir`/`DestDir`:

| nzbfast | Set via | Equivalent |
|---|---|---|
| out dir | `persistence.downloads.mountPath` (becomes `NZBFAST_OUT`) | NZBGet `InterDir` |
| `move_completed` | `settings.values.move_completed` (absolute path) | NZBGet `DestDir` |
| `move_completed_cats` | `settings.values`, `"cat=/abs/path, cat2=/abs/path2"` | NZBGet `CategoryN.DestDir` |

So: point `persistence.downloads` at a fast local volume, and
`move_completed` at the library share your *arr apps import from. The finished
release is moved there in one bulk copy at the end.

`write_through: true` writes straight to the destination instead, skipping the
move. Upstream advises against it for network shares — it pays per-write
latency across the whole download rather than one bulk copy.

## Extra init containers

`extraInitContainers` runs before the chart's own config-placing one. This is
where shared-media permission fixing goes when several apps write to one
volume as different uids:

```yaml
extraInitContainers:
  - name: fix-media-permissions
    image: busybox:latest
    command: [/bin/sh, -c]
    args:
      - |
        chown root:65534 /media /media/library
        chmod 2775 /media /media/library
    volumeMounts:
      - name: media
        mountPath: /media/
```

## Connecting Sonarr/Radarr

nzbfast speaks the SABnzbd API. Add it as a **SABnzbd** download client:

- Host: `<release>-nzbfast.<namespace>.svc.cluster.local`
- Port: `service.port` (default `80`)
- API key: as above

## Metrics

`GET /metrics`, Prometheus text format. Either set
`settings.values.metrics_open: true` for unauthenticated scraping, or give
Prometheus the API key. `metrics.serviceMonitor.enabled: true` creates a
ServiceMonitor.

## Notes and caveats

- **Single instance.** `controller.replicas` above 1 is rejected by the chart:
  two pods against one `/config` corrupt the index and queue spool.
- **Port is locked.** The image sets `NZBFAST_PORT_LOCKED=1`, so the port field
  in the dashboard is read-only — it belongs to the Service, not the UI.
- **Probes use `mode=version`**, which needs no API key; this is the same
  endpoint the image's own `HEALTHCHECK` calls.
- **`settings.mode: merge` pulls a second image** (`ghcr.io/mikefarah/yq`) for
  the init container. The other modes use the nzbfast image itself.
