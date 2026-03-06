{{/*
CertChain Showroom — template helpers
*/}}

{{- define "certchain-showroom.labels" -}}
app.kubernetes.io/part-of: certchain
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}
