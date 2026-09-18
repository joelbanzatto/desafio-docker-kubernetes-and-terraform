{{- define "mural.fullname" -}}
mural
{{- end -}}

{{- define "mural.labels" -}}
app.kubernetes.io/name: {{ include "mural.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
