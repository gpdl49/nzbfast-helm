{{/* Chart name, overridable. */}}
{{- define "nzbfast.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nzbfast.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "nzbfast.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nzbfast.labels" -}}
helm.sh/chart: {{ include "nzbfast.chart" . }}
{{ include "nzbfast.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: downloader
app.kubernetes.io/part-of: nzbfast
{{- end -}}

{{- define "nzbfast.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nzbfast.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "nzbfast.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "nzbfast.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* Image ref: digest wins over tag. */}}
{{- define "nzbfast.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}
{{- end -}}

{{- define "nzbfast.mergeToolImage" -}}
{{- $m := .Values.settings.mergeTool -}}
{{- if $m.digest -}}
{{- printf "%s@%s" $m.repository $m.digest -}}
{{- else -}}
{{- printf "%s:%s" $m.repository $m.tag -}}
{{- end -}}
{{- end -}}

{{/* Names of the Secrets holding the two rendered files. */}}
{{- define "nzbfast.configSecretName" -}}
{{- if .Values.config.existingSecret -}}
{{- .Values.config.existingSecret -}}
{{- else -}}
{{- printf "%s-config-json" (include "nzbfast.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "nzbfast.settingsSecretName" -}}
{{- if .Values.settings.existingSecret -}}
{{- .Values.settings.existingSecret -}}
{{- else -}}
{{- printf "%s-settings-json" (include "nzbfast.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "nzbfast.apiKeySecretName" -}}
{{- if .Values.apiKey.existingSecret -}}
{{- .Values.apiKey.existingSecret -}}
{{- else -}}
{{- printf "%s-apikey" (include "nzbfast.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/* Do we render (rather than reference) each file? */}}
{{- define "nzbfast.renderConfig" -}}
{{- if and (ne .Values.config.mode "disabled") (not .Values.config.existingSecret) -}}true{{- end -}}
{{- end -}}

{{- define "nzbfast.renderSettings" -}}
{{- if and (ne .Values.settings.mode "disabled") (not .Values.settings.existingSecret) -}}true{{- end -}}
{{- end -}}

{{/* Is either file being placed into /config by an init container? */}}
{{- define "nzbfast.manageConfig" -}}
{{- if ne .Values.config.mode "disabled" -}}true{{- end -}}
{{- end -}}

{{- define "nzbfast.manageSettings" -}}
{{- if ne .Values.settings.mode "disabled" -}}true{{- end -}}
{{- end -}}

{{/*
config.json body. serde on the Rust side takes defaults for every field but
`host`, and `skip_serializing_if` means absent is meaningfully different from
zero for several of them — so emit only what the user actually set.
*/}}
{{- define "nzbfast.configJson" -}}
{{- $servers := list -}}
{{- range .Values.config.servers -}}
  {{- $s := dict "host" (required "config.servers[].host is required" .host) -}}
  {{- if hasKey . "port" }}{{- $_ := set $s "port" (int .port) }}{{- end -}}
  {{- if hasKey . "tls" }}{{- $_ := set $s "tls" .tls }}{{- end -}}
  {{- if hasKey . "username" }}{{- $_ := set $s "username" .username }}{{- end -}}
  {{- if hasKey . "password" }}{{- $_ := set $s "password" .password }}{{- end -}}
  {{- if hasKey . "connections" }}{{- $_ := set $s "connections" (int .connections) }}{{- end -}}
  {{- if hasKey . "level" }}{{- $_ := set $s "level" (int .level) }}{{- end -}}
  {{- if hasKey . "enabled" }}{{- $_ := set $s "enabled" .enabled }}{{- end -}}
  {{- if hasKey . "retention_days" }}{{- $_ := set $s "retention_days" (int .retention_days) }}{{- end -}}
  {{- if hasKey . "block_account" }}{{- $_ := set $s "block_account" .block_account }}{{- end -}}
  {{- if hasKey . "block_bytes" }}{{- $_ := set $s "block_bytes" (int64 .block_bytes) }}{{- end -}}
  {{- if hasKey . "group" }}{{- $_ := set $s "group" .group }}{{- end -}}
  {{- if hasKey . "pin_connections" }}{{- $_ := set $s "pin_connections" .pin_connections }}{{- end -}}
  {{- if hasKey . "warm_pool" }}{{- $_ := set $s "warm_pool" .warm_pool }}{{- end -}}
  {{- if hasKey . "warm_reserve" }}{{- $_ := set $s "warm_reserve" (int .warm_reserve) }}{{- end -}}
  {{- if hasKey . "address_family" }}{{- $_ := set $s "address_family" .address_family }}{{- end -}}
  {{- if hasKey . "tls_hostname" }}{{- $_ := set $s "tls_hostname" .tls_hostname }}{{- end -}}
  {{- if hasKey . "bind_ip" }}{{- $_ := set $s "bind_ip" .bind_ip }}{{- end -}}
  {{- if hasKey . "socks5" }}{{- $_ := set $s "socks5" .socks5 }}{{- end -}}
  {{- if hasKey . "rcvbuf" }}{{- $_ := set $s "rcvbuf" (int .rcvbuf) }}{{- end -}}
  {{- if hasKey . "idle_keep" }}{{- $_ := set $s "idle_keep" (int .idle_keep) }}{{- end -}}
  {{- if hasKey . "idle_release_secs" }}{{- $_ := set $s "idle_release_secs" (int .idle_release_secs) }}{{- end -}}
  {{- if hasKey . "max_source_ips" }}{{- $_ := set $s "max_source_ips" (int .max_source_ips) }}{{- end -}}
  {{- $servers = append $servers $s -}}
{{- end -}}
{{- $cfg := dict "servers" $servers -}}
{{- if .Values.config.tmdbKey }}{{- $_ := set $cfg "tmdb_key" .Values.config.tmdbKey }}{{- end -}}
{{- toPrettyJson $cfg -}}
{{- end -}}

{{- define "nzbfast.settingsJson" -}}
{{- toPrettyJson .Values.settings.values -}}
{{- end -}}
