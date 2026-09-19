{{/*
Resource name. The release name IS the service name by convention —
helm upgrade --install <service> helm/petclinic-service/ -f helm-values/<service>.yaml -f helm-values/<env>.yaml
— so no separate nameOverride/fullnameOverride indirection is needed.
*/}}
{{- define "petclinic-service.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{/*
Common labels — the four app.kubernetes.io/* keys used across k8s/base/*.
*/}}
{{- define "petclinic-service.labels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.fullname" . }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: {{ .Values.component }}
{{- end -}}

{{/*
Selector labels — deliberately just app.kubernetes.io/name, matching the
Service selector / Deployment matchLabels already in k8s/base/*.
*/}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.fullname" . }}
{{- end -}}
