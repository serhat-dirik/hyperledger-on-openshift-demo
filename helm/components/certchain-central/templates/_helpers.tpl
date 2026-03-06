{{/*
Common labels applied to all resources.
*/}}
{{- define "certchain-central.labels" -}}
app.kubernetes.io/part-of: certchain
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Image helper — resolves image ref from global or component values.
Usage: {{ include "certchain-central.image" (dict "reg" .Values.global.registry "repo" .Values.certPortal.image.repository "tag" .Values.certPortal.image.tag "globalTag" .Values.global.imageTag) }}
*/}}
{{- define "certchain-central.appImage" -}}
{{- $repo := .repo | default (printf "%s/%s" .reg .name) -}}
{{- $tag := .tag | default .globalTag | default "latest" -}}
{{ printf "%s:%s" $repo $tag }}
{{- end }}
