#!/usr/bin/env bash
# Render the qui PrometheusRule and run promtool on it: syntax check, then the alert unit tests.
# Usage: hack/test-alerts.sh   (needs helm, python3 with pyyaml, and promtool on PATH)
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

helm template ci charts/qui --namespace ci --values charts/qui/ci/monitoring-values.yaml --skip-tests \
  | python3 -c 'import sys, yaml
rules = [d for d in yaml.safe_load_all(sys.stdin) if d and d.get("kind") == "PrometheusRule"]
yaml.safe_dump(rules[0]["spec"], sys.stdout)' > "$work/rules.yaml"
cp charts/qui/tests/alerts/*.yaml "$work/"

cd "$work"
promtool check rules rules.yaml
promtool test rules ./*-test.yaml
