{{/*
Expand the name of the chart.
*/}}
{{- define "csdp-add-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "csdp-add-cluster.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "csdp-add-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "csdp-add-cluster.labels" -}}
helm.sh/chart: {{ include "csdp-add-cluster.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Creates the ServiceAccount name (used for the *Role and *RoleBinding as well)
Based on the "argocd-manager" unless explicitly set
*/}}
{{- define "csdp-add-cluster.serviceAccountName" -}}
  {{- if .Values.serviceAccount.create }}
    {{- default (include "csdp-add-cluster.fullname" .) .Values.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/*
Environment variable value of Codefresh installation token
*/}}
{{- define "csdp-add-cluster.token-env-var-value" -}}
  {{- if .Values.codefresh.userToken }}
valueFrom:
  secretKeyRef:
    name: {{ include "csdp-add-cluster.fullname" . }}-secret
    key: codefresh-api-token
  {{- else if .Values.codefresh.userToken.secretKeyRef  }}
valueFrom:
  secretKeyRef:
  {{- .Values.codefresh.userToken.secretKeyRef | toYaml | nindent 4 }}
  {{- end }}
{{- end }}