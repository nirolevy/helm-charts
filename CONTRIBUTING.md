# Contributing

Issues and pull requests are welcome.

## Setup

Tools: [Helm](https://helm.sh), [helm-unittest](https://github.com/helm-unittest/helm-unittest),
[chart-testing](https://github.com/helm/chart-testing), [pre-commit](https://pre-commit.com), and [kind](https://kind.sigs.k8s.io) for install tests.

```sh
pre-commit install
```

## Checks

```sh
pre-commit run --all-files                    # formatting, yamllint, helm-docs, workflow linters
ct lint --config ct.yaml --lint-conf .yamllint.yaml
helm dependency build charts/<chart> && helm unittest --strict charts/<chart>
ct install --config ct.yaml                   # on a kind cluster
python3 hack/check-qui-config.py              # qui only: list qui settings missing from values.yaml
```

## Rules

1. Bump `version` in the chart's `Chart.yaml` for every change to the chart, including `ci/` and `tests/`.
   Patch for fixes, minor for features, major for breaking changes. CI checks this.
2. Document every value with a `# --` comment. pre-commit regenerates the chart README with helm-docs.
3. Add unit tests in `charts/<chart>/tests/` and an install case in `charts/<chart>/ci/` when it makes sense.
4. Describe breaking changes under "Upgrading" in `README.md.gotmpl`.
5. Pull requests are rebase-merged, so every commit lands on `main` as written. Give each commit a
   [Conventional Commits](https://www.conventionalcommits.org) message, for example `feat(qui): add ...`,
   and keep each commit working on its own.

## Adding a chart

1. Create `charts/<name>/` with the bjw-s common library as a dependency (see `charts/qui`).
2. Add `ci/default-values.yaml`, unit tests and a `README.md.gotmpl`.
3. Add the chart to the table in the root `README.md`.

## Releases

Merging a new chart version into `main` releases it. No manual steps.

Each pull request bumps the version of the charts it changes (the chart-testing convention). A pull request
must be up to date with `main` before it merges, so CI checks its version against the latest release and two
pull requests cannot claim the same version. Renovate rebases its pull requests when `main` moves. As a last
guard, the release workflow fails instead of reusing or overwriting a released version.
