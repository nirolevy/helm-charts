#!/usr/bin/env bash
# Usage: hack/annotate.sh <title> <file>
# Writes the end of <file> as one GitHub Actions error annotation.
set -euo pipefail
title=$1
file=$2
[ -f "$file" ] || exit 0
# Annotation messages are URL-style encoded: %, CR and LF must be escaped.
body=$(tail -c 12000 "$file" | sed -e 's/%/%25/g' -e 's/\r/%0D/g' | awk 'BEGIN{ORS="%0A"} {print}')
echo "::error title=${title}::${body}"
