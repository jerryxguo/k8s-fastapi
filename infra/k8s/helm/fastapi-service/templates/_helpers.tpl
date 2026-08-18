{{- define "fastapi-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "fastapi-service.fullname" -}}
{{- .Values.serviceAccount.name | default (include "fastapi-service.name" .) -}}
{{- end -}}

{{- define "fastapi-service.labels" -}}
app.kubernetes.io/name: {{ include "fastapi-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "fastapi-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fastapi-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
