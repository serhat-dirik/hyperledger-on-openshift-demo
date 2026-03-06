{{/*
Common labels applied to all resources.
*/}}
{{- define "certchain-org.labels" -}}
app.kubernetes.io/part-of: certchain
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
certchain/org: {{ .Values.org.name }}
{{- end }}

{{/*
Org namespace — certchain-<orgname>
*/}}
{{- define "certchain-org.namespace" -}}
{{ .Values.global.centralNamespace }}-{{ .Values.org.name }}
{{- end }}

{{/*
Local orderer name — maps org name to orderer name for ExternalName skip logic.
*/}}
{{- define "certchain-org.localOrderer" -}}
{{- if eq .Values.org.name "techpulse" }}orderer1
{{- else if eq .Values.org.name "dataforge" }}orderer2
{{- else if eq .Values.org.name "neuralpath" }}orderer3
{{- end -}}
{{- end }}
