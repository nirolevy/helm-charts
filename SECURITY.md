# Security policy

## Supported versions

Only the latest version of each chart receives fixes.

## Reporting a vulnerability

Report vulnerabilities in the charts privately with
[GitHub private vulnerability reporting](https://github.com/nirolevy/helm-charts/security/advisories/new).
Do not open a public issue.

Report vulnerabilities in an application to its own project, for example
[autobrr/qui](https://github.com/autobrr/qui/security/policy).

## Verifying releases

OCI artifacts are signed with keyless cosign through GitHub Actions OIDC, and packages carry a GitHub build provenance
attestation. The root README shows the verify commands.
