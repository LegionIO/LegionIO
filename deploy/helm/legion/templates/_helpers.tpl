{{- define "legion.fullname" -}}
{{- .Release.Name }}-legion
{{- end }}

{{- define "legion.labels" -}}
app.kubernetes.io/name: legion
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "legion.selectorLabels" -}}
app.kubernetes.io/name: legion
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
