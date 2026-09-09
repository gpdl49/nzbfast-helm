{{/*
Volume name for a persistence entry: the existing claim keeps its own name so
a StatefulSet that adopts one reads clearly in `kubectl describe`.
*/}}
{{- define "nzbfast.claimName" -}}
{{- $ctx := index . 0 -}}{{- $key := index . 1 -}}
{{- $p := index $ctx.Values.persistence $key -}}
{{- if $p.existingClaim -}}
{{- $p.existingClaim -}}
{{- else -}}
{{- printf "%s-%s" (include "nzbfast.fullname" $ctx) $key -}}
{{- end -}}
{{- end -}}

{{/* The init container's shell program: place config.json and settings.json. */}}
{{- define "nzbfast.initScript" -}}
set -eu

say() { echo "nzbfast-init: $*"; }

mkdir -p /config

{{- if include "nzbfast.manageConfig" . }}

# ---- config.json -----------------------------------------------------------
SRC=/helm/config/{{ .Values.config.existingSecretKey }}
DST=/config/config.json
{{- if eq .Values.config.mode "enforce" }}
say "config.json: enforce - rewriting from Helm values"
cp "$SRC" "$DST.tmp"
mv "$DST.tmp" "$DST"
{{- else if eq .Values.config.mode "seed" }}
if [ -f "$DST" ]; then
  say "config.json: seed - already present, leaving it alone"
else
  say "config.json: seed - writing initial file"
  cp "$SRC" "$DST.tmp"
  mv "$DST.tmp" "$DST"
fi
{{- end }}
chmod 600 "$DST"
{{- end }}

{{- if include "nzbfast.manageSettings" . }}

# ---- settings.json ---------------------------------------------------------
SRC=/helm/settings/{{ .Values.settings.existingSecretKey }}
DST=/config/settings.json
{{- if eq .Values.settings.mode "merge" }}
if [ -f "$DST" ]; then
  say "settings.json: merge - Helm keys over the file on disk"
  # Deep-merge, right-hand side wins. Maps merge recursively; arrays are
  # REPLACED, so a list in Helm values owns that key outright.
  yq -o=json -P eval-all '. as $item ireduce ({}; . * $item)' "$DST" "$SRC" > "$DST.tmp"
  # Only swap in a non-empty result: a merge that produced nothing means the
  # on-disk file was unreadable, and clobbering it would lose the API key.
  if [ -s "$DST.tmp" ]; then
    mv "$DST.tmp" "$DST"
  else
    say "settings.json: merge produced an empty result - keeping the existing file"
    rm -f "$DST.tmp"
  fi
else
  say "settings.json: merge - no file yet, writing Helm values as the initial file"
  cp "$SRC" "$DST.tmp"
  mv "$DST.tmp" "$DST"
fi
{{- else if eq .Values.settings.mode "enforce" }}
say "settings.json: enforce - replacing the file wholesale"
cp "$SRC" "$DST.tmp"
mv "$DST.tmp" "$DST"
{{- else if eq .Values.settings.mode "seed" }}
if [ -f "$DST" ]; then
  say "settings.json: seed - already present, leaving it alone"
else
  say "settings.json: seed - writing initial file"
  cp "$SRC" "$DST.tmp"
  mv "$DST.tmp" "$DST"
fi
{{- end }}
{{- end }}

{{- if not .Values.rootless }}

# The app entrypoint only chowns /config when the DIRECTORY's owner differs
# from PUID, so files this container just created as root would otherwise
# stay root-owned inside an already-correct directory.
chown {{ .Values.puid }}:{{ .Values.pgid }} /config/config.json /config/settings.json 2>/dev/null || true
{{- end }}

say "done"
{{- end -}}


{{/* The pod template, shared by the StatefulSet and Deployment forms. */}}
{{- define "nzbfast.podSpec" -}}
metadata:
  labels:
    {{- include "nzbfast.selectorLabels" . | nindent 4 }}
    {{- with .Values.controller.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    {{- if .Values.controller.restartOnConfigChange }}
    {{- if include "nzbfast.renderConfig" . }}
    checksum/config: {{ include "nzbfast.configJson" . | sha256sum }}
    {{- end }}
    {{- if include "nzbfast.renderSettings" . }}
    checksum/settings: {{ include "nzbfast.settingsJson" . | sha256sum }}
    {{- end }}
    {{- end }}
    {{- with .Values.controller.podAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  serviceAccountName: {{ include "nzbfast.serviceAccountName" . }}
  automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken }}
  {{- with .Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.priorityClassName }}
  priorityClassName: {{ . }}
  {{- end }}
  {{- if .Values.hostNetwork }}
  hostNetwork: true
  {{- end }}
  {{- with .Values.dnsPolicy }}
  dnsPolicy: {{ . }}
  {{- end }}
  {{- with .Values.dnsConfig }}
  dnsConfig:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
  securityContext:
    {{- toYaml .Values.podSecurityContext | nindent 4 }}
    {{- if .Values.rootless }}
    runAsNonRoot: true
    runAsUser: {{ .Values.puid }}
    runAsGroup: {{ .Values.pgid }}
    {{- end }}
  {{- if or (include "nzbfast.manageConfig" .) (include "nzbfast.manageSettings" .) }}
  initContainers:
    - name: place-config
      {{- if eq .Values.settings.mode "merge" }}
      image: {{ include "nzbfast.mergeToolImage" . }}
      imagePullPolicy: {{ .Values.settings.mergeTool.pullPolicy }}
      {{- else }}
      image: {{ include "nzbfast.image" . }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      {{- end }}
      command: [/bin/sh, -c]
      args:
        - |
          {{- include "nzbfast.initScript" . | nindent 10 }}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: false
        capabilities:
          drop: [ALL]
          {{- if not .Values.rootless }}
          add: [CHOWN, FOWNER, DAC_OVERRIDE]
          {{- end }}
        {{- if not .Values.rootless }}
        runAsUser: 0
        {{- end }}
      resources:
        {{- toYaml .Values.initResources | nindent 8 }}
      volumeMounts:
        - name: config
          mountPath: /config
        {{- if include "nzbfast.manageConfig" . }}
        - name: helm-config
          mountPath: /helm/config
          readOnly: true
        {{- end }}
        {{- if include "nzbfast.manageSettings" . }}
        - name: helm-settings
          mountPath: /helm/settings
          readOnly: true
        {{- end }}
  {{- end }}
  containers:
    - name: nzbfast
      image: {{ include "nzbfast.image" . }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      securityContext:
        {{- $sc := deepCopy .Values.securityContext }}
        {{- if .Values.rootless }}
        {{- $_ := unset $sc.capabilities "add" }}
        {{- end }}
        {{- toYaml $sc | nindent 8 }}
      env:
        - name: NZBFAST_CONFIG
          value: /config/config.json
        - name: NZBFAST_PORT
          value: {{ .Values.service.targetPort | quote }}
        - name: NZBFAST_OUT
          value: {{ .Values.persistence.downloads.mountPath | quote }}
        - name: NZBFAST_WATCH
          value: {{ .Values.persistence.watch.mountPath | quote }}
        {{- if not .Values.persistence.config.enabled }}
        # /config is an emptyDir here, so silence the "your settings will be
        # deleted with this container" warning the entrypoint prints.
        - name: NZBFAST_ALLOW_EPHEMERAL_CONFIG
          value: "1"
        {{- end }}
        {{- if not .Values.rootless }}
        - name: PUID
          value: {{ .Values.puid | quote }}
        - name: PGID
          value: {{ .Values.pgid | quote }}
        {{- end }}
        {{- if .Values.apiKey.open }}
        - name: NZBFAST_OPEN
          value: "1"
        {{- else if or .Values.apiKey.value .Values.apiKey.existingSecret }}
        - name: NZBFAST_APIKEY
          valueFrom:
            secretKeyRef:
              name: {{ include "nzbfast.apiKeySecretName" . }}
              key: {{ .Values.apiKey.existingSecretKey }}
        {{- end }}
        {{- with .Values.timezone }}
        - name: TZ
          value: {{ . | quote }}
        {{- end }}
        {{- range $k, $v := .Values.env }}
        - name: {{ $k }}
          value: {{ $v | quote }}
        {{- end }}
        {{- with .Values.extraEnv }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with .Values.extraEnvFrom }}
      envFrom:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      ports:
        - name: http
          containerPort: {{ .Values.service.targetPort }}
          protocol: TCP
      {{- if .Values.probes.startup.enabled }}
      startupProbe:
        httpGet:
          path: {{ .Values.probes.path | quote }}
          port: http
        {{- omit .Values.probes.startup "enabled" | toYaml | nindent 8 }}
      {{- end }}
      {{- if .Values.probes.liveness.enabled }}
      livenessProbe:
        httpGet:
          path: {{ .Values.probes.path | quote }}
          port: http
        {{- omit .Values.probes.liveness "enabled" | toYaml | nindent 8 }}
      {{- end }}
      {{- if .Values.probes.readiness.enabled }}
      readinessProbe:
        httpGet:
          path: {{ .Values.probes.path | quote }}
          port: http
        {{- omit .Values.probes.readiness "enabled" | toYaml | nindent 8 }}
      {{- end }}
      resources:
        {{- toYaml .Values.resources | nindent 8 }}
      volumeMounts:
        - name: config
          mountPath: /config
        {{- if .Values.persistence.downloads.enabled }}
        - name: downloads
          mountPath: {{ .Values.persistence.downloads.mountPath }}
        {{- end }}
        {{- if .Values.persistence.watch.enabled }}
        - name: watch
          mountPath: {{ .Values.persistence.watch.mountPath }}
        {{- end }}
        {{- if .Values.persistence.incomplete.enabled }}
        - name: incomplete
          mountPath: {{ .Values.persistence.incomplete.mountPath }}
        {{- end }}
        {{- with .Values.extraVolumeMounts }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
  volumes:
    {{- if .Values.persistence.config.enabled }}
    - name: config
      persistentVolumeClaim:
        claimName: {{ include "nzbfast.claimName" (list . "config") }}
    {{- else }}
    - name: config
      emptyDir: {}
    {{- end }}
    {{- range $key := list "downloads" "watch" "incomplete" }}
    {{- $p := index $.Values.persistence $key }}
    {{- if $p.enabled }}
    - name: {{ $key }}
      persistentVolumeClaim:
        claimName: {{ include "nzbfast.claimName" (list $ $key) }}
    {{- end }}
    {{- end }}
    {{- if include "nzbfast.manageConfig" . }}
    - name: helm-config
      secret:
        secretName: {{ include "nzbfast.configSecretName" . }}
        defaultMode: 0440
    {{- end }}
    {{- if include "nzbfast.manageSettings" . }}
    - name: helm-settings
      secret:
        secretName: {{ include "nzbfast.settingsSecretName" . }}
        defaultMode: 0440
    {{- end }}
    {{- with .Values.extraVolumes }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.topologySpreadConstraints }}
  topologySpreadConstraints:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
