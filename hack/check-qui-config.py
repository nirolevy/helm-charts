#!/usr/bin/env python3
"""Report qui settings that values.yaml does not list in `qui.config`.

Reads internal/config/config.go of the qui release in Chart.yaml `appVersion`
and exits 1 when:
  * a qui setting is missing from `qui.config` in values.yaml (and is not a
    credential or a chart-managed setting), or
  * the chart renders a different variable name than the one qui reads.

Unlisted settings still work through `qui.config` or the container env, so this
is only a documentation reminder: the qui-settings workflow opens an issue.

Usage: python3 hack/check-qui-config.py [path/to/config.go]
"""
import pathlib
import re
import subprocess
import sys
import urllib.request

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHART = ROOT / "charts" / "qui"

# Settings that belong in `qui.secret`.
SECRET_KEYS = {"sessionSecret", "databaseDsn", "databasePassword", "oidcClientSecret", "metricsBasicAuthUsers"}
# Settings the chart derives from `service.app.ports` (metricsHost can still be set in `qui.config`).
CHART_MANAGED = {"port", "metricsEnabled", "metricsHost", "metricsPort"}
# qui's viper key for this setting is not camelCase; the chart uses iAcknowledgeThisIsABadIdea.
KEY_ALIASES = {"I_ACKNOWLEDGE_THIS_IS_A_BAD_IDEA": "iAcknowledgeThisIsABadIdea"}

BIND_RE = re.compile(r'(?:BindEnv|bindOrReadFromFile)\("([^"]+)",\s*envPrefix\s*\+\s*"([A-Z0-9_]+)"\)')


def qui_source(argv):
    if len(argv) > 1:
        return pathlib.Path(argv[1]).read_text()
    chart = yaml.safe_load((CHART / "Chart.yaml").read_text())
    url = f"https://raw.githubusercontent.com/autobrr/qui/{chart['appVersion']}/internal/config/config.go"
    print(f"Reading {url}")
    with urllib.request.urlopen(url, timeout=30) as resp:
        return resp.read().decode()


def main(argv):
    bound = {KEY_ALIASES.get(k, k): "QUI__" + env for k, env in BIND_RE.findall(qui_source(argv))}
    if len(bound) < 10:
        sys.exit(f"Found only {len(bound)} bound variables; the qui source layout probably changed")

    values = yaml.safe_load((CHART / "values.yaml").read_text())
    documented = set(values["qui"]["config"])
    errors = []

    for key in sorted(bound):
        if key not in documented | SECRET_KEYS | CHART_MANAGED:
            errors.append(f"qui setting {key} ({bound[key]}) is not in values.yaml `qui.config`")
    for key in sorted(documented - set(bound)):
        errors.append(f"values.yaml `qui.config.{key}` is not a qui environment setting")

    # Render every setting and compare the variable names with qui's.
    args = ["helm", "template", "check", str(CHART), "--skip-schema-validation"]
    for key in sorted(set(bound) - SECRET_KEYS - {"port"}):
        args += ["--set-string", f"qui.config.{key}=x"]
    for key in sorted(SECRET_KEYS & set(bound)):
        args += ["--set-string", f"qui.secret.values.{key}=x"]
    rendered = subprocess.run(args, check=True, capture_output=True, text=True).stdout
    # Plain settings are env entries; credentials are keys of the chart Secret.
    names = set(re.findall(r"name: (QUI__[A-Z0-9_]+)", rendered))
    names |= set(re.findall(r"^\s+(QUI__[A-Z0-9_]+):", rendered, re.M))
    for key, env in sorted(bound.items()):
        if env not in names:
            errors.append(f"{key} should render as {env}, which the chart does not produce")

    if errors:
        print("\n".join(errors))
        sys.exit(1)
    print(f"All {len(bound)} qui environment settings are covered")


if __name__ == "__main__":
    main(sys.argv)
