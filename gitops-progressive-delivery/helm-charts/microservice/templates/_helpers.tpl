{{/*
Expand the name of the chart.
*/}}
{{- define "microservice.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "microservice.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "microservice.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "microservice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "microservice.selectorLabels" -}}
app.kubernetes.io/name: {{ include "microservice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
OTel service name — defaults to Release.Name
*/}}
{{- define "microservice.otelServiceName" -}}
{{ .Release.Name }}
{{- end }}

{{/*
Canary service name
*/}}
{{- define "microservice.canaryService" -}}
{{- if .Values.rollout.canary.canaryService }}
{{- .Values.rollout.canary.canaryService }}
{{- else }}
{{- include "microservice.fullname" . }}-canary
{{- end }}
{{- end }}

{{/*
Stable service name
*/}}
{{- define "microservice.stableService" -}}
{{- if .Values.rollout.canary.stableService }}
{{- .Values.rollout.canary.stableService }}
{{- else }}
{{- include "microservice.fullname" . }}-stable
{{- end }}
{{- end }}
