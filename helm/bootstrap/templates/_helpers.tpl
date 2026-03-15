{{/*
Compute the target Git repo URL for child ArgoCD Applications.
When Gitea is enabled: use the Gitea internal URL.
When Gitea is disabled: use sourceRepo.url (user's fork).
*/}}
{{- define "bootstrap.targetRepoUrl" -}}
{{- if .Values.gitea.enabled -}}
https://gitea-{{ .Values.gitea.namespace }}.{{ .Values.deployer.domain }}/{{ .Values.gitea.orgName }}/{{ .Values.gitea.repoName }}.git
{{- else -}}
{{ .Values.sourceRepo.url }}
{{- end -}}
{{- end -}}

{{- define "bootstrap.targetRevision" -}}
{{ .Values.sourceRepo.revision }}
{{- end -}}

{{- define "bootstrap.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: certchain
{{- end -}}
