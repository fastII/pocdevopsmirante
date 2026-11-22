{{/*
Expand the name of the chart.
*/}}
{{- define "pocapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pocapp.fullname" -}}
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
{{- define "pocapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pocapp.labels" -}}
{{ include "pocapp.commonLabels" . }}
{{ include "pocapp.selectorLabels" . }}
{{- end }}

{{- define "pocapp.commonLabels" -}}
helm.sh/chart: {{ include "pocapp.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "pocapp.canaryFullname" -}}
{{- printf "%s-canary" (include "pocapp.fullname" . | trunc 56 | trimSuffix "-") -}}
{{- end }}

{{- define "pocapp.canarySelectorLabels" -}}
app.kubernetes.io/name: {{ printf "%s-canary" (include "pocapp.name" . | trunc 56 | trimSuffix "-") }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pocapp.workloads" -}}
{{- $stable := dict "name" (include "pocapp.fullname" .) "selector" (include "pocapp.selectorLabels" .) "image" .Values.image "canary" false -}}
{{- $workloads := list $stable -}}
{{- if .Values.canary.enabled -}}
  {{- if not .Values.httpRoute.enabled -}}
    {{- fail "canary.enabled requer httpRoute.enabled" -}}
  {{- end -}}
  {{- if not (regexMatch "^([0-9]|[1-9][0-9]|100)$" (toString .Values.canary.weight)) -}}
    {{- fail "canary.weight deve ser um inteiro entre 0 e 100" -}}
  {{- end -}}
  {{- $image := dict "repository" (default .Values.image.repository .Values.canary.image.repository) "tag" (required "defina canary.image.tag" .Values.canary.image.tag) "pullPolicy" .Values.canary.image.pullPolicy -}}
  {{- $candidate := dict "name" (include "pocapp.canaryFullname" .) "selector" (include "pocapp.canarySelectorLabels" .) "image" $image "canary" true -}}
  {{- if or (eq $stable.name $candidate.name) (eq $stable.selector $candidate.selector) -}}
    {{- fail "os nomes e seletores do canary e da versão estável precisam ser distintos" -}}
  {{- end -}}
  {{- $workloads = append $workloads $candidate -}}
{{- end -}}
{{- toYaml $workloads -}}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pocapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pocapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "pocapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pocapp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
