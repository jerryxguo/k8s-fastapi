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

{{- /*
Celery worker. Its own app.kubernetes.io/name, not just an extra component
label: the API's Service, PDB and topology-spread selectors match on
name + instance, so worker pods sharing those would receive HTTP traffic
and count toward the API's disruption budget.
*/ -}}
{{- define "fastapi-service.worker.fullname" -}}
{{- printf "%s-worker" (include "fastapi-service.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "fastapi-service.worker.serviceAccountName" -}}
{{- .Values.worker.serviceAccount.name | default (include "fastapi-service.worker.fullname" .) -}}
{{- end -}}

{{- define "fastapi-service.worker.selectorLabels" -}}
app.kubernetes.io/name: {{ printf "%s-worker" (include "fastapi-service.name" .) | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: worker
{{- end -}}

{{- define "fastapi-service.worker.labels" -}}
{{ include "fastapi-service.worker.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
