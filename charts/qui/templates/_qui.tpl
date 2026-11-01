{{/*
qui-specific logic on top of the bjw-s common library.
It runs after the library merged its defaults and before it renders, and turns `qui.*`
into common library values: env vars, a Secret, and the config.toml init container.
*/}}

{{/*
config.toml key (camelCase) to its QUI__ variable name.
fooBar -> QUI__FOO_BAR, databaseSSLMode -> QUI__DATABASE_SSL_MODE,
authDisabledAllowedCIDRs -> QUI__AUTH_DISABLED_ALLOWED_CIDRS
*/}}
{{- define "qui.envName" -}}
{{- $name := regexReplaceAll "([A-Z]{2,})s([A-Z]|$)" . "${1}S${2}" }}
{{- $name = regexReplaceAll "([A-Z]+)([A-Z][a-z])" $name "${1}_${2}" }}
{{- $name = regexReplaceAll "([a-z0-9])([A-Z])" $name "${1}_${2}" }}
{{- printf "QUI__%s" (upper $name) }}
{{- end }}

{{/*
A config value as a variable value. Lists are comma-separated; whole numbers lose the ".0" YAML gives them.
*/}}
{{- define "qui.envValue" -}}
{{- if kindIs "slice" . }}
{{- join "," . }}
{{- else if and (kindIs "float64" .) (eq (float64 (int64 .)) .) }}
{{- int64 . }}
{{- else }}
{{- toString . }}
{{- end }}
{{- end }}

{{/*
"true" when a config value should be rendered: not null and not an empty list.
*/}}
{{- define "qui.isSet" -}}
{{- if not (or (kindIs "invalid" .) (and (kindIs "slice" .) (eq (len .) 0))) }}true{{ end }}
{{- end }}

{{/*
The port qui listens on: the target port (or port) of service.app.ports.<name>.
*/}}
{{- define "qui.servicePort" -}}
{{- $port := dig "service" "app" "ports" .name dict .root.Values }}
{{- int64 (default $port.port $port.targetPort) }}
{{- end }}

{{/*
Name of an object the chart adds: <fullname>-<suffix>. Fixed, because the library otherwise
names an object by how many of its kind exist, and a renamed Secret breaks references to it.
*/}}
{{- define "qui.resourceName" -}}
{{- printf "%s-%s" (include "bjw-s.common.lib.chart.names.fullname" .root | trunc (int (sub 62 (len .suffix)))) .suffix | trimSuffix "-" }}
{{- end }}

{{/*
Fail early on values that would deploy a broken qui.
*/}}
{{- define "qui.validate" -}}
{{- $qui := .Values.qui }}
{{- $controller := dig "controllers" "qui" dict .Values }}
{{- if not (dig "containers" "app" false $controller) }}
{{- fail "controllers.qui.containers.app is required: the chart configures qui through these identifiers" }}
{{- end }}
{{- if not (dig "service" "app" "ports" "http" false .Values) }}
{{- fail "service.app.ports.http is required: qui listens on its port" }}
{{- end }}
{{- range $name := list "http" "metrics" }}
{{- with dig "service" "app" "ports" $name "targetPort" nil $.Values }}
{{- if not (regexMatch "^[0-9]+$" (toString .)) }}
{{- fail (printf "service.app.ports.%s.targetPort must be a number: qui listens on it" $name) }}
{{- end }}
{{- end }}
{{- end }}
{{- if gt (int (dig "replicas" 1 $controller)) 1 }}
{{- fail "controllers.qui.replicas must be 0 or 1: a second qui runs the same background jobs and, with SQLite, shares one database file" }}
{{- end }}
{{- $config := $qui.config }}
{{- if and (include "qui.isSet" $config.port) (ne (int64 $config.port) (int64 (include "qui.servicePort" (dict "root" . "name" "http")))) }}
{{- fail "qui.config.port differs from service.app.ports.http; set the port in service.app.ports.http only" }}
{{- end }}
{{- range $key, $_ := $qui.secret.values }}
{{- if include "qui.isSet" (index $config $key) }}
{{- fail (printf "%s is set in both qui.config and qui.secret.values; set it in one place" $key) }}
{{- end }}
{{- end }}
{{- $pvc := dig "persistence" "config" dict .Values }}
{{- if and (dig "enabled" true $pvc) (eq (dig "type" "persistentVolumeClaim" $pvc) "persistentVolumeClaim") (eq (dig "accessMode" "ReadWriteOnce" $pvc) "ReadWriteOnce") (ne (toString (dig "strategy" "Recreate" $controller)) "Recreate") }}
{{- fail "controllers.qui.strategy must be Recreate with a ReadWriteOnce config volume: a second pod cannot attach it" }}
{{- end }}
{{- with $qui.configFile }}
{{- if and .enabled (not .content) }}
{{- fail "qui.configFile.enabled needs qui.configFile.content" }}
{{- end }}
{{- if and .enabled .overwrite (not (hasKey $qui.secret.values "sessionSecret")) (not $qui.secret.existingSecret) (not (regexMatch "(?m)^\\s*sessionSecret\\s*=" .content)) }}
{{- fail "qui.configFile.overwrite replaces config.toml on every start: set sessionSecret in qui.configFile.content, qui.secret.values or qui.secret.existingSecret, or qui cannot decrypt stored credentials after a restart" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Translate `qui.*` into common library values (mutates .Values).
*/}}
{{- define "qui.applyValues" -}}
{{- $root := . }}
{{- $qui := .Values.qui }}
{{- $container := .Values.controllers.qui.containers.app }}

{{- /* Monitoring needs the metrics server and its Service port. */ -}}
{{- $monitoring := $qui.monitoring }}
{{- if or $monitoring.serviceMonitor.enabled $monitoring.prometheusRule.enabled $monitoring.grafanaDashboard.enabled }}
{{- $metricsPort := dig "service" "app" "ports" "metrics" dict .Values }}
{{- if not $metricsPort }}
{{- fail "qui.monitoring needs service.app.ports.metrics: qui serves metrics on that port" }}
{{- end }}
{{- $_ := set $metricsPort "enabled" true }}
{{- end }}
{{- include "qui.monitoring" . }}

{{- /* Settings the chart derives from the Service. */ -}}
{{- $config := deepCopy $qui.config }}
{{- $_ := set $config "port" (include "qui.servicePort" (dict "root" . "name" "http")) }}
{{- $metrics := dig "service" "app" "ports" "metrics" dict .Values }}
{{- if and $metrics (dig "enabled" true $metrics) }}
{{- $_ := set $config "metricsEnabled" true }}
{{- if not (include "qui.isSet" (index $config "metricsHost")) }}
{{- $_ := set $config "metricsHost" "0.0.0.0" }}
{{- end }}
{{- $_ := set $config "metricsPort" (include "qui.servicePort" (dict "root" . "name" "metrics")) }}
{{- end }}

{{- with $qui.extraArgs }}
{{- $_ := set $container "args" (concat (default list $container.args) .) }}
{{- end }}

{{- /* Named container ports that follow the Service; the probes use "http". */ -}}
{{- if not $container.ports }}
{{- $ports := list (dict "name" "http" "containerPort" (int64 $config.port) "protocol" "TCP") }}
{{- if $config.metricsEnabled }}
{{- $ports = append $ports (dict "name" "metrics" "containerPort" (int64 $config.metricsPort) "protocol" "TCP") }}
{{- end }}
{{- $_ := set $container "ports" $ports }}
{{- end }}

{{- /* Chart env vars, as a map. User-defined env (map or list) wins over them. */ -}}
{{- $env := dict }}
{{- range $key, $value := $config }}
{{- if include "qui.isSet" $value }}
{{- $_ := set $env (include "qui.envName" $key) (include "qui.envValue" $value) }}
{{- end }}
{{- end }}
{{- $userEnv := $container.env }}
{{- if kindIs "slice" $userEnv }}
{{- range $userEnv }}
{{- $_ := set $env .name (omit . "name") }}
{{- end }}
{{- else if kindIs "map" $userEnv }}
{{- $env = merge (deepCopy $userEnv) $env }}
{{- end }}
{{- $_ := set $container "env" $env }}

{{- /* Credentials: a chart Secret and/or an existing Secret, loaded with envFrom. */ -}}
{{- $envFrom := default list $container.envFrom }}
{{- if $qui.secret.values }}
{{- $data := dict }}
{{- range $key, $value := $qui.secret.values }}
{{- $_ := set $data (include "qui.envName" $key) (include "qui.envValue" $value) }}
{{- end }}
{{- $secrets := default dict .Values.secrets }}
{{- $_ := set $secrets "qui-env" (dict "enabled" true "forceRename" (include "qui.resourceName" (dict "root" $ "suffix" "env")) "stringData" $data) }}
{{- $_ := set .Values "secrets" $secrets }}
{{- $envFrom = append $envFrom (dict "secretRef" (dict "identifier" "qui-env")) }}
{{- end }}
{{- with $qui.secret.existingSecret }}
{{- $envFrom = append $envFrom (dict "secretRef" (dict "name" .)) }}
{{- end }}
{{- if $envFrom }}
{{- $_ := set $container "envFrom" $envFrom }}
{{- end }}

{{- /* config.toml: a ConfigMap copied into /config by an init container. */ -}}
{{- if $qui.configFile.enabled }}
{{- $configMaps := default dict .Values.configMaps }}
{{- $_ := set $configMaps "qui-config-file" (dict "enabled" true "forceRename" (include "qui.resourceName" (dict "root" $ "suffix" "config-file")) "data" (dict "config.toml" $qui.configFile.content)) }}
{{- $_ := set .Values "configMaps" $configMaps }}
{{- $persistence := default dict .Values.persistence }}
{{- $mount := list (dict "path" "/chart-config" "readOnly" true) }}
{{- $_ := set $persistence "qui-config-file" (dict "enabled" true "type" "configMap" "identifier" "qui-config-file" "advancedMounts" (dict "qui" (dict "config-file" $mount))) }}
{{- /* The init container writes into whatever volume the app container mounts at /config. */ -}}
{{- range $name, $volume := $persistence }}
{{- range $path := dig "advancedMounts" "qui" "app" list $volume }}
{{- if eq (trimSuffix "/" $path.path) "/config" }}
{{- $mounts := $volume.advancedMounts.qui }}
{{- $_ := set $mounts "config-file" (append (default list (index $mounts "config-file")) (omit $path "readOnly")) }}
{{- end }}
{{- end }}
{{- end }}
{{- $_ := set .Values "persistence" $persistence }}
{{- $script := include "qui.configFileScript" . }}
{{- $init := dict
  "image" (deepCopy $container.image)
  "command" (list "/bin/sh" "-ec" $script)
  "securityContext" (deepCopy (default dict $container.securityContext))
  "resources" (dict "requests" (dict "cpu" "10m" "memory" "16Mi") "limits" (dict "memory" "64Mi"))
}}
{{- $controller := .Values.controllers.qui }}
{{- $inits := default dict $controller.initContainers }}
{{- $_ := set $inits "config-file" (merge (default dict (index $inits "config-file")) $init) }}
{{- $_ := set $controller "initContainers" $inits }}
{{- end }}
{{- end }}

{{/*
Init container script that installs config.toml.
*/}}
{{- define "qui.configFileScript" -}}
target=/config/config.toml
{{- if .Values.qui.configFile.overwrite }}
echo "Writing $target from the chart"
{{- else }}
if [ -e "$target" ]; then
  echo "$target exists, keeping it"
  exit 0
fi
echo "Creating $target from the chart"
{{- end }}
umask 077
cp /chart-config/config.toml "$target.tmp"
mv "$target.tmp" "$target"
{{- end }}

{{/*
Monitoring objects from `qui.monitoring`: a library ServiceMonitor, and a PrometheusRule and a
Grafana Operator GrafanaDashboard as library rawResources (mutates .Values).
*/}}
{{- define "qui.monitoring" -}}
{{- $m := .Values.qui.monitoring }}

{{- with $m.serviceMonitor }}
{{- if .enabled }}
{{- $endpoint := merge (deepCopy .endpoint) (dict "port" "metrics" "path" "/metrics" "scheme" "http" "interval" .interval "scrapeTimeout" .scrapeTimeout) }}
{{- $monitors := default dict $.Values.serviceMonitor }}
{{- $_ := set $monitors "qui" (dict "enabled" true "labels" .labels "service" (dict "identifier" "app") "endpoints" (list $endpoint)) }}
{{- $_ := set $.Values "serviceMonitor" $monitors }}
{{- end }}
{{- end }}

{{- $raw := default dict .Values.rawResources }}

{{- with $m.prometheusRule }}
{{- if .enabled }}
{{- $service := include "bjw-s.common.lib.service.getByIdentifier" (dict "rootContext" $ "id" "app") | fromYaml }}
{{- $selector := printf "namespace=%q, service=%q" $.Release.Namespace $service.name }}
{{- $alerts := list
  (dict "alert" "QuiDown"
    "expr" (printf "up{%s} == 0" $selector)
    "for" "5m"
    "labels" (dict "severity" "critical")
    "annotations" (dict "summary" "qui is down" "description" "Prometheus cannot scrape the qui metrics endpoint. qui cannot report this itself."))
  (dict "alert" "QuiQbittorrentInstanceDown"
    "expr" (printf "qbittorrent_instance_connection_status{%s} == 0" $selector)
    "for" "10m"
    "labels" (dict "severity" "warning")
    "annotations" (dict "summary" "A qBittorrent instance is disconnected" "description" "qui reports the instance in the instance_name label as unhealthy or disabled. Disabled instances also report 0; disable this alert or add an alert label matcher if you keep instances disabled."))
  (dict "alert" "QuiCollectionErrors"
    "expr" (printf "sum by (namespace, service, instance_name, type) (sum_over_time(qbittorrent_scrape_errors_total{%s}[5m])) > 0" $selector)
    "for" "15m"
    "labels" (dict "severity" "warning")
    "annotations" (dict "summary" "qui cannot collect qBittorrent metrics" "description" "qui failed to collect metrics from the instance in the instance_name label for 15 minutes."))
  (dict "alert" "QuiDatabaseWedgedTransactions"
    "expr" (printf "increase(qui_db_wedged_transaction_total{%s}[1h]) > 0" $selector)
    "labels" (dict "severity" "warning")
    "annotations" (dict "summary" "qui detected wedged SQLite transactions" "description" "qui detected nested SQLite transactions in the last hour. Check the qui logs."))
}}
{{- $rules := list }}
{{- range $alerts }}
{{- if not (has .alert $m.prometheusRule.disabledAlerts) }}
{{- $_ := set . "labels" (merge (deepCopy $m.prometheusRule.alertLabels) .labels) }}
{{- $rules = append $rules . }}
{{- end }}
{{- end }}
{{- $rules = concat $rules (default list .additionalRules) }}
{{- $manifest := dict
  "apiVersion" "monitoring.coreos.com/v1"
  "kind" "PrometheusRule"
  "metadata" (dict "labels" .labels)
  "spec" (dict "groups" (list (dict "name" "qui" "rules" $rules)))
}}
{{- $_ := set $raw "qui-prometheus-rule" (dict "enabled" true "forceRename" (include "qui.resourceName" (dict "root" $ "suffix" "rules")) "manifest" $manifest) }}
{{- end }}
{{- end }}

{{- with $m.grafanaDashboard }}
{{- if .enabled }}
{{- /* The dashboard of the deployed qui release; a non-release tag (latest, develop) falls back to appVersion. */ -}}
{{- $tag := toString (dig "controllers" "qui" "containers" "app" "image" "tag" "" $.Values) }}
{{- if not (regexMatch "^v[0-9]+\\.[0-9]+\\.[0-9]+$" $tag) }}
{{- $tag = $.Chart.AppVersion }}
{{- end }}
{{- $url := default (printf "https://raw.githubusercontent.com/autobrr/qui/%s/documentation/static/examples/qui-grafana-dashboard.json" $tag) .url }}
{{- $spec := dict
  "url" $url
  "instanceSelector" .instanceSelector
  "resyncPeriod" .resyncPeriod
  "allowCrossNamespaceImport" .allowCrossNamespaceImport
  "datasources" (list (dict "inputName" "DS_PROMETHEUS" "datasourceName" .datasourceName))
}}
{{- with .folder }}
{{- $_ := set $spec "folder" . }}
{{- end }}
{{- $manifest := dict
  "apiVersion" "grafana.integreatly.org/v1beta1"
  "kind" "GrafanaDashboard"
  "metadata" (dict "labels" .labels)
  "spec" $spec
}}
{{- $_ := set $raw "qui-grafana-dashboard" (dict "enabled" true "forceRename" (include "qui.resourceName" (dict "root" $ "suffix" "dashboard")) "manifest" $manifest) }}
{{- end }}
{{- end }}

{{- if $raw }}
{{- $_ := set .Values "rawResources" $raw }}
{{- end }}
{{- end }}
