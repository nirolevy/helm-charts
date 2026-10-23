# Helm charts

[![CI](https://github.com/nirolevy/helm-charts/actions/workflows/ci.yaml/badge.svg)](https://github.com/nirolevy/helm-charts/actions/workflows/ci.yaml)
[![Release](https://github.com/nirolevy/helm-charts/actions/workflows/release.yaml/badge.svg)](https://github.com/nirolevy/helm-charts/actions/workflows/release.yaml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nirolevy/helm-charts/badge)](https://scorecard.dev/viewer/?uri=github.com/nirolevy/helm-charts)

Helm charts for self-hosted applications, published to a Helm repository on GitHub Pages and as signed OCI artifacts on GitHub Container Registry.

## Usage

Add the repository once:

```sh
helm repo add nirolevy https://nirolevy.github.io/helm-charts
helm repo update
helm search repo nirolevy
```

Or install straight from the OCI registry:

```sh
helm install <release> oci://ghcr.io/nirolevy/charts/<chart>
```

## Charts

| Chart | Application | Documentation |
| --- | --- | --- |
| [qui](charts/qui) | [qui](https://github.com/autobrr/qui), a web UI for managing multiple qBittorrent instances | [README](charts/qui/README.md) |

The charts are built on the [bjw-s common library](https://github.com/bjw-s-labs/helm-charts), so they share one values format
for workloads, storage, networking and monitoring.

## Verifying releases

Every OCI artifact is signed with keyless [cosign](https://github.com/sigstore/cosign), and every package has a GitHub build provenance attestation:

```sh
cosign verify ghcr.io/nirolevy/charts/<chart>:<version> \
  --certificate-identity-regexp '^https://github.com/nirolevy/helm-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify <chart>-<version>.tgz --repo nirolevy/helm-charts
```

## How the repository works

- **CI**: [pre-commit](.pre-commit-config.yaml) hooks (yamllint, helm-docs, actionlint, zizmor, gitleaks, Renovate config),
  [chart-testing](https://github.com/helm/chart-testing) lint with a version-bump check,
  [helm-unittest](https://github.com/helm-unittest/helm-unittest), and `ct install` with `helm test` and upgrade tests on
  [kind](https://kind.sigs.k8s.io) for three Kubernetes versions.
- **Releases**: [chart-releaser](https://github.com/helm/chart-releaser-action) publishes each new chart version as a GitHub release and in the
  Pages index. The same package is pushed to `ghcr.io`, signed and attested.
- **Updates**: [Renovate](https://docs.renovatebot.com) opens pull requests for new app releases, the common library, actions, hooks
  and tools, with the chart version already bumped. Everything is pinned by version and digest.
- **Security**: OpenSSF Scorecard and CodeQL.
- **qui settings**: a weekly job opens an issue when a qui release adds settings that `values.yaml` does not document yet.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE). The packaged applications have their own licenses.
