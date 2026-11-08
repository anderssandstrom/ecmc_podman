#!/bin/bash
set -euo pipefail
# URL, revision (tag/branch/SHA), destination. Never build an implicit branch tip.
url=$1 ref=$2 destination=$3
if [[ ! -d $destination/.git ]]; then git init "$destination"; fi
if git -C "$destination" remote get-url origin >/dev/null 2>&1; then
    git -C "$destination" remote set-url origin "$url"
else
    git -C "$destination" remote add origin "$url"
fi
git -C "$destination" fetch --depth 1 "$url" "$ref"
git -C "$destination" checkout --detach FETCH_HEAD
git -C "$destination" submodule update --init --recursive
printf '%s %s %s\n' "$destination" "$url" "$(git -C "$destination" rev-parse HEAD)" >> /opt/source-revisions.txt
