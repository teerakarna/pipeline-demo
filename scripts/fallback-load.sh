#!/usr/bin/env bash
# Build one image per button colour on this Mac and load them onto the Pi, no GitHub involved.
#   scripts/fallback-load.sh v3 [user@pipeline-pi.local]
# The images are tagged fallback-<colour>; the page shows the version you give. Colima must be running.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?usage: fallback-load.sh <version> [user@host]}
PI=${2:-${PI:-}}; [ -n "$PI" ] || { echo "say which Pi: fallback-load.sh $VERSION user@pipeline-pi.local"; exit 1; }
IMAGE=ghcr.io/teerakarna/pipeline-demo
COLOURS=$(python3 -c 'import re;print(re.search(r"ALLOWED_COLOURS = \[(.*?)\]", open("app/main.py").read()).group(1).replace("\"","").replace(",",""))')

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tags=()
for c in $COLOURS; do
  rm -rf "${tmp:?}/src"; mkdir "$tmp/src"
  git archive HEAD | tar -x -C "$tmp/src"                          # committed code only
  sed -i.bak "s/^BUTTON_COLOUR = .*/BUTTON_COLOUR = \"$c\"/" "$tmp/src/app/main.py"
  docker build -q --build-arg APP_VERSION="$VERSION" -t "$IMAGE:fallback-$c" "$tmp/src" >/dev/null
  tags+=("$IMAGE:fallback-$c"); echo "built fallback-$c"
done
echo "loading ${#tags[@]} images onto $PI ..."
docker save "${tags[@]}" | ssh "$PI" 'sudo k3s ctr -n k8s.io images import -'
ssh "$PI" 'sudo k3s crictl images | grep fallback'
