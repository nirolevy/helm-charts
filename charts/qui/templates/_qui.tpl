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
{{- $_ := set $secrets "qui-env" (dict "enabled" true "stringData" $data) }}
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
{{- $_ := set $configMaps "qui-config-file" (dict "enabled" true "data" (dict "config.toml" $qui.configFile.content)) }}
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
