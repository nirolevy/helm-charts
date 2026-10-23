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
5. Use [Conventional Commits](https://www.conventionalcommits.org) for pull request titles, for example `feat(qui): add ...`.

## Adding a chart

1. Create `charts/<name>/` with the bjw-s common library as a dependency (see `charts/qui`).
2. Add `ci/default-values.yaml`, unit tests and a `README.md.gotmpl`.
3. Add the chart to the table in the root `README.md`.

## Releases

Merging a new chart version into `main` releases it. No manual steps.
