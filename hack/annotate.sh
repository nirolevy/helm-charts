#!/usr/bin/env bash
# Usage: hack/annotate.sh <title> <file>
# Writes the end of <file> as GitHub Actions error annotations. GitHub keeps 4 KB per
# annotation and 10 error annotations per step, so the last ~28 KB go out in 7 chunks.
set -euo pipefail
title=$1
file=$2
[ -f "$file" ] || exit 0
chunks=$(mktemp -d)
tail -c 28000 "$file" | split -C 3500 - "$chunks/part-"
i=0
total=$(find "$chunks" -type f | wc -l)
for part in "$chunks"/part-*; do
  i=$((i + 1))
  # Annotation messages are URL-style encoded: %, CR and LF must be escaped.
  body=$(sed -e 's/%/%25/g' -e 's/\r/%0D/g' "$part" | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=${title} (${i}/${total})::${body}"
done
rm -rf "$chunks"
