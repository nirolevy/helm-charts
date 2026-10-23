# qui

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v1.33.1](https://img.shields.io/badge/AppVersion-v1.33.1-informational?style=flat-square)

qui, a fast, modern web interface for managing multiple qBittorrent instances

[qui](https://github.com/autobrr/qui) is made by the autobrr project. This chart is a community project and is not affiliated with it.

## Install

From the Helm repository:

```sh
helm repo add nirolevy https://nirolevy.github.io/helm-charts
helm install qui nirolevy/qui --namespace qui --create-namespace
```

Or from the OCI registry:

```sh
helm install qui oci://ghcr.io/nirolevy/charts/qui --namespace qui --create-namespace
```

Then open the UI and create the admin account:

```sh
kubectl --namespace qui port-forward svc/qui 7476
```

Requirements: Kubernetes `>=1.31.0-0`, Helm 3.8 or later.

## How the chart works

The chart is built on the [bjw-s common library](https://github.com/bjw-s-labs/helm-charts) (`5.3.0`),
the library behind [app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/).
Workloads, volumes, Services, Ingress, Gateway API routes, ServiceMonitors, NetworkPolicies and extra resources use its
values format. The [app-template documentation](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) describes every option.

On top of the library, the chart adds `qui`:

- **`qui.config`**: every qui setting by its `config.toml` name. Each key becomes a `QUI__*` variable, for example
  `logLevel` becomes `QUI__LOG_LEVEL`. Unset keys are not rendered. Settings that a newer qui adds work without
  a chart update: `someNewSetting` becomes `QUI__SOME_NEW_SETTING`.
- **`qui.secret`**: credentials, from `values` (the chart creates a Secret) or from `existingSecret`.
- **`qui.configFile`**: a full `config.toml`, for settings without a variable such as `externalProgramAllowList`.
- **`qui.extraArgs`**: arguments appended after `serve`.

The chart also sets the listen port from `service.app.ports.http`, enables the metrics server when
`service.app.ports.metrics` is enabled, and sends probes with `Host: localhost` so `allowedHosts` cannot block them.

Settings set through variables are locked in the qui UI.

For anything else, use the library directly: `controllers.qui.containers.app.env`, `envFrom`, `args`, `command`,
extra `persistence` entries, sidecars under `controllers.qui.containers`, init containers, or `rawResources`.
Keep the identifiers `controllers.qui`, its container `app`, and `service.app`.

## Examples

### Ingress with TLS

```yaml
qui:
  config:
    allowedHosts: [qui.example.com]
    sessionCookieSecure: true
ingress:
  app:
    className: nginx
    hosts:
      - host: qui.example.com
        paths:
          - path: /
            service:
              identifier: app
              port: http
    tls:
      - hosts: [qui.example.com]
        secretName: qui-tls
```

### Gateway API

```yaml
route:
  app:
    parentRefs:
      - name: public
        namespace: gateway
    hostnames: [qui.example.com]
    rules:
      - backendRefs:
          - identifier: app
            port: 7476
```

### Session secret

qui encrypts stored qBittorrent passwords with the session secret. Without one, qui generates a secret on first start
and keeps it in `config.toml` on the config volume. To manage it yourself:

```sh
kubectl --namespace qui create secret generic qui-env \
  --from-literal=QUI__SESSION_SECRET="$(openssl rand -hex 32)"
```

```yaml
qui:
  secret:
    existingSecret: qui-env
```

On an existing install, reuse the `sessionSecret` from `/config/config.toml`. A new value makes stored credentials unreadable.

### Postgres

```yaml
qui:
  config:
    databaseEngine: postgres
  secret:
    existingSecret: qui-env # QUI__DATABASE_DSN=postgres://user:password@host:5432/qui?sslmode=require
```

### OIDC

```yaml
qui:
  config:
    oidcEnabled: true
    oidcIssuer: https://auth.example.com
    oidcClientId: qui
    oidcRedirectUrl: https://qui.example.com/api/auth/oidc/callback
  secret:
    existingSecret: qui-env # QUI__OIDC_CLIENT_SECRET
```

### Local filesystem access

Orphan scan, hardlinks, reflinks and path-based automations need the paths qBittorrent uses, at the same location:

```yaml
persistence:
  downloads:
    existingClaim: downloads
    advancedMounts:
      qui:
        app:
          - path: /downloads
defaultPodOptions:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000 # the owner of the downloads
    runAsGroup: 1000
    fsGroup: 1000
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile:
      type: RuntimeDefault
```

Then enable **Local Filesystem Access** for the instance in the qui UI.

### Prometheus metrics

```yaml
service:
  app:
    ports:
      metrics:
        enabled: true
serviceMonitor:
  app:
    labels:
      release: kube-prometheus-stack
    service:
      identifier: app
    endpoints:
      - port: metrics
        path: /metrics
        interval: 30s
```

### Settings without a variable

```yaml
qui:
  configFile:
    enabled: true
    overwrite: true # the chart owns config.toml; log settings changed in the UI reset on restart
    content: |
      externalProgramAllowList = ["/config/scripts"]
  secret:
    existingSecret: qui-env # must contain QUI__SESSION_SECRET when overwrite is true
```

### Anything else

```yaml
controllers:
  qui:
    containers:
      app:
        env:
          TZ: Europe/Berlin
          QUI__SESSION_SECRET_FILE: /secrets/session
qui:
  extraArgs: [--pprof]
persistence:
  secrets:
    type: secret
    name: qui-files
    advancedMounts:
      qui:
        app:
          - path: /secrets
            readOnly: true
```

## Security defaults

The pod runs as user 1000:1000 with a read-only root filesystem, no capabilities, `RuntimeDefault` seccomp and no
ServiceAccount token. qui writes only to `/config` and `/tmp`.

## Schema validation

`values.schema.json` checks the `qui` values and, through the library's published schema, everything else.
Helm downloads that schema from `raw.githubusercontent.com`. Without internet access, install with `--skip-schema-validation`.

## Verify a release

```sh
cosign verify ghcr.io/nirolevy/charts/qui:0.1.0 \
  --certificate-identity-regexp '^https://github.com/nirolevy/helm-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify qui-0.1.0.tgz --repo nirolevy/helm-charts
```

## Upgrading

The chart follows [semantic versioning](https://semver.org). Major versions list required value changes here.

## Uninstall

```sh
helm uninstall qui --namespace qui
```

The config PersistentVolumeClaim is kept (`persistence.config.retain`). Delete it yourself to remove the data.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| controllers.qui.containers.app.args[0] | string | `"serve"` |  |
| controllers.qui.containers.app.image.pullPolicy | string | `"IfNotPresent"` |  |
| controllers.qui.containers.app.image.repository | string | `"ghcr.io/autobrr/qui"` |  |
| controllers.qui.containers.app.image.tag | string | `"{{ .Chart.AppVersion }}"` |  |
| controllers.qui.containers.app.probes.liveness.custom | bool | `true` |  |
| controllers.qui.containers.app.probes.liveness.enabled | bool | `true` |  |
| controllers.qui.containers.app.probes.liveness.spec.failureThreshold | int | `3` |  |
| controllers.qui.containers.app.probes.liveness.spec.httpGet.httpHeaders[0].name | string | `"Host"` |  |
| controllers.qui.containers.app.probes.liveness.spec.httpGet.httpHeaders[0].value | string | `"localhost"` |  |
| controllers.qui.containers.app.probes.liveness.spec.httpGet.path | string | `"/healthz/liveness"` |  |
| controllers.qui.containers.app.probes.liveness.spec.httpGet.port | string | `"http"` |  |
| controllers.qui.containers.app.probes.liveness.spec.periodSeconds | int | `30` |  |
| controllers.qui.containers.app.probes.liveness.spec.timeoutSeconds | int | `5` |  |
| controllers.qui.containers.app.probes.readiness.custom | bool | `true` |  |
| controllers.qui.containers.app.probes.readiness.enabled | bool | `true` |  |
| controllers.qui.containers.app.probes.readiness.spec.failureThreshold | int | `3` |  |
| controllers.qui.containers.app.probes.readiness.spec.httpGet.httpHeaders[0].name | string | `"Host"` |  |
| controllers.qui.containers.app.probes.readiness.spec.httpGet.httpHeaders[0].value | string | `"localhost"` |  |
| controllers.qui.containers.app.probes.readiness.spec.httpGet.path | string | `"/healthz/readiness"` |  |
| controllers.qui.containers.app.probes.readiness.spec.httpGet.port | string | `"http"` |  |
| controllers.qui.containers.app.probes.readiness.spec.periodSeconds | int | `10` |  |
| controllers.qui.containers.app.probes.readiness.spec.timeoutSeconds | int | `5` |  |
| controllers.qui.containers.app.probes.startup.custom | bool | `true` |  |
| controllers.qui.containers.app.probes.startup.enabled | bool | `true` |  |
| controllers.qui.containers.app.probes.startup.spec.failureThreshold | int | `60` |  |
| controllers.qui.containers.app.probes.startup.spec.httpGet.httpHeaders[0].name | string | `"Host"` |  |
| controllers.qui.containers.app.probes.startup.spec.httpGet.httpHeaders[0].value | string | `"localhost"` |  |
| controllers.qui.containers.app.probes.startup.spec.httpGet.path | string | `"/healthz/liveness"` |  |
| controllers.qui.containers.app.probes.startup.spec.httpGet.port | string | `"http"` |  |
| controllers.qui.containers.app.probes.startup.spec.periodSeconds | int | `5` |  |
| controllers.qui.containers.app.probes.startup.spec.timeoutSeconds | int | `3` |  |
| controllers.qui.containers.app.resources.limits.memory | string | `"1Gi"` |  |
| controllers.qui.containers.app.resources.requests.cpu | string | `"50m"` |  |
| controllers.qui.containers.app.resources.requests.memory | string | `"128Mi"` |  |
| controllers.qui.containers.app.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| controllers.qui.containers.app.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| controllers.qui.containers.app.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| controllers.qui.replicas | int | `1` |  |
| controllers.qui.strategy | string | `"Recreate"` |  |
| controllers.qui.type | string | `"deployment"` |  |
| defaultPodOptions.automountServiceAccountToken | bool | `false` |  |
| defaultPodOptions.enableServiceLinks | bool | `false` |  |
| defaultPodOptions.securityContext.fsGroup | int | `1000` |  |
| defaultPodOptions.securityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| defaultPodOptions.securityContext.runAsGroup | int | `1000` |  |
| defaultPodOptions.securityContext.runAsNonRoot | bool | `true` |  |
| defaultPodOptions.securityContext.runAsUser | int | `1000` |  |
| defaultPodOptions.securityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| ingress | object | `{}` |  |
| networkpolicies | object | `{}` |  |
| persistence.config.accessMode | string | `"ReadWriteOnce"` |  |
| persistence.config.advancedMounts.qui.app[0].path | string | `"/config"` |  |
| persistence.config.enabled | bool | `true` | Persist `/config` (config.toml, SQLite database, backups). Set `existingClaim` to reuse a claim. |
| persistence.config.retain | bool | `true` | Keep the claim when the release is uninstalled. |
| persistence.config.size | string | `"1Gi"` |  |
| persistence.config.type | string | `"persistentVolumeClaim"` |  |
| persistence.tmp.advancedMounts.qui.app[0].path | string | `"/tmp"` |  |
| persistence.tmp.sizeLimit | string | `"256Mi"` |  |
| persistence.tmp.type | string | `"emptyDir"` |  |
| qui.config | object | see below | qui settings, rendered as `QUI__*` environment variables on the `app` container. Keys are the `config.toml` names from the [configuration reference](https://getqui.com/docs/configuration/reference). Unset (`null`) keys are not rendered, so qui keeps its default or the value in `config.toml`. Lists render comma-separated. A key the chart does not list still works: `fooBarBaz` renders as `QUI__FOO_BAR_BAZ`. Variables lock the matching fields in the qui UI. The chart sets `port` from `service.app.ports.http`, and the metrics settings from `service.app.ports.metrics`. Put credentials in `qui.secret`. |
| qui.config.allowedHosts | list | `[]` | Allowed `Host` values (hostnames, IPs or `*.` wildcards). Empty allows any host. The default probes send `Host: localhost`, which qui always allows. |
| qui.config.authDisabled | bool | `nil` | Disable built-in authentication. Needs `iAcknowledgeThisIsABadIdea` and `authDisabledAllowedCIDRs`. |
| qui.config.authDisabledAllowedCIDRs | list | `[]` | IPs or CIDRs allowed when authentication is disabled. |
| qui.config.backupDir | string | `nil` | Backup directory. Defaults to `<dataDir>/backups`. |
| qui.config.baseUrl | string | `nil` | Serve qui from a sub path, for example `/qui/`. |
| qui.config.checkForUpdates | bool | `nil` | Check for new qui releases. |
| qui.config.corsAllowedOrigins | list | `[]` | Explicit CORS origins. Empty disables CORS. |
| qui.config.crossSeedRecoverErroredTorrents | bool | `nil` | Let cross-seed recover errored or missingFiles torrents (slow). |
| qui.config.customThemesDir | string | `nil` | Directory for custom theme `.css` files. Defaults to `/config/themes`. |
| qui.config.dataDir | string | `nil` | Directory for the SQLite database, tracker icons and backups. Defaults to `/config`. |
| qui.config.databaseConnMaxLifetime | int | `nil` | Postgres maximum connection lifetime in seconds. |
| qui.config.databaseConnectTimeout | int | `nil` | Postgres connect timeout in seconds. |
| qui.config.databaseEngine | string | `nil` | Database engine: `sqlite` or `postgres`. |
| qui.config.databaseHost | string | `nil` | Postgres host, when not using a DSN. |
| qui.config.databaseMaxIdleConns | int | `nil` | Postgres pool maximum idle connections. |
| qui.config.databaseMaxOpenConns | int | `nil` | Postgres pool maximum open connections. |
| qui.config.databaseName | string | `nil` | Postgres database name, when not using a DSN. |
| qui.config.databasePort | int | `nil` | Postgres port, when not using a DSN. |
| qui.config.databaseSSLMode | string | `nil` | Postgres SSL mode: `disable`, `require`, `verify-ca` or `verify-full`. |
| qui.config.databaseUser | string | `nil` | Postgres user, when not using a DSN. |
| qui.config.disableSelfUpdate | bool | `nil` | Hide Self-update in the UI. qui already disables it in Kubernetes. |
| qui.config.externalProgramMaxRunning | int | `nil` | Maximum number of external programs that run at the same time. |
| qui.config.host | string | `"0.0.0.0"` | Listen address. |
| qui.config.iAcknowledgeThisIsABadIdea | bool | `nil` | Confirmation required to disable authentication. |
| qui.config.logLevel | string | `nil` | Log level: `ERROR`, `WARN`, `INFO`, `DEBUG` or `TRACE`. qui defaults to `DEBUG`. |
| qui.config.logMaxBackups | int | `nil` | Rotated log files to keep, 0 keeps all (with `logPath`). |
| qui.config.logMaxSize | int | `nil` | Log size in MB that starts a rotation (with `logPath`). |
| qui.config.logPath | string | `nil` | Log file path. Unset logs to stdout. |
| qui.config.oidcClientId | string | `nil` | OIDC client ID. |
| qui.config.oidcDisableBuiltInLogin | bool | `nil` | Hide the built-in login form (with OIDC). |
| qui.config.oidcEnabled | bool | `nil` | Enable OpenID Connect login. |
| qui.config.oidcIssuer | string | `nil` | OIDC issuer URL. |
| qui.config.oidcRedirectUrl | string | `nil` | OIDC redirect URL, for example `https://qui.example.com/api/auth/oidc/callback`. |
| qui.config.pprofAddr | string | `nil` | pprof bind address. |
| qui.config.pprofEnabled | bool | `nil` | Enable the pprof server. |
| qui.config.qbittorrentTimeout | int | `nil` | HTTP timeout in seconds for requests to qBittorrent. |
| qui.config.sessionCookieSecure | bool | `nil` | Send the session cookie only over HTTPS. Enable behind an HTTPS ingress. |
| qui.config.trackerIconsFetchEnabled | bool | `nil` | Fetch tracker favicons from trackers. |
| qui.configFile.content | string | `""` | `config.toml` content (TOML, templated). With `overwrite`, set `sessionSecret` here or in `qui.secret`, or qui generates a new one on every start and cannot decrypt stored credentials. |
| qui.configFile.enabled | bool | `false` | Write `config.toml` before qui starts, for settings without a variable (for example `externalProgramAllowList`). Variables from `qui.config` and `qui.secret` still win. |
| qui.configFile.overwrite | bool | `true` | `true` replaces `config.toml` on every start. `false` writes it only if none exists. |
| qui.extraArgs | list | `[]` | Arguments appended to `controllers.qui.containers.app.args`, for example `["--pprof"]`. For extra environment variables use `controllers.qui.containers.app.env` (map or list) and `envFrom`. |
| qui.secret.existingSecret | string | `""` | Existing Secret loaded with `envFrom`. Its keys must be variable names, for example `QUI__SESSION_SECRET`. |
| qui.secret.values | object | `{}` | Credentials by `config.toml` name (`sessionSecret`, `databasePassword`, `databaseDsn`, `oidcClientSecret`, `metricsBasicAuthUsers`, ...). Stored in a Secret the chart creates. Prefer `existingSecret`, so credentials stay out of values files. |
| route | object | `{}` |  |
| service.app.controller | string | `"qui"` |  |
| service.app.ports.http.port | int | `7476` |  |
| service.app.ports.metrics.enabled | bool | `false` | Expose the qui metrics server. The chart enables it in qui and binds it to all interfaces. |
| service.app.ports.metrics.port | int | `9074` |  |
| serviceMonitor | object | `{}` |  |
