#!/usr/bin/env bash
# Deploy an image that is already on the Pi, by hand, when GitHub is slow or down.
#   pi/fallback-deploy.sh green        (uses the image fallback-green)
# Stops the release loop first, otherwise it would roll back to the newest release.
set -euo pipefail
IMAGE=${IMAGE:-ghcr.io/teerakarna/pipeline-demo}
KUBECTL=${KUBECTL:-kubectl}
tag=fallback-${1:?usage: fallback-deploy.sh <colour>}

echo "$(date +%T) stopping the release loop"
if command -v systemctl >/dev/null; then sudo systemctl stop release-loop || true; else echo "(no systemd here, loop not stopped)"; fi
$KUBECTL set image deploy/pipeline-demo app="$IMAGE:$tag"
$KUBECTL rollout status deploy/pipeline-demo --timeout=120s
echo "$(date +%T) $tag is live. Resume the loop with: sudo systemctl start release-loop"
