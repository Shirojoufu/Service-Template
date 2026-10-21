{{/* Namespaces the policies skip: the configured list plus our own. */}}
{{- define "policy-webhook.excludedNamespaces" -}}
{{- append .Values.webhook.excludedNamespaces .Release.Namespace | uniq | toJson -}}
{{- end -}}

{{- define "policy-webhook.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "policy-webhook.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
