#!/usr/bin/env bash
# Release loop: keep the cluster running the newest release.
# Watch it live with: journalctl -fu release-loop
REPO=${REPO:-https://github.com/teerakarna/pipeline-demo}
IMAGE=${IMAGE:-ghcr.io/teerakarna/pipeline-demo}
MANIFEST=${MANIFEST:-/opt/pipeline-demo/app.yaml}
KUBECTL=${KUBECTL:-kubectl}
EVERY=${EVERY:-5}
TIMEOUT=${TIMEOUT:-120}

say() { echo "$(date +%T) $*"; }
latest() { git ls-remote --tags --refs "$REPO" 'v*' | sed 's|.*refs/tags/||' | sort -V | tail -1; }
running() { $KUBECTL get deploy pipeline-demo -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's|.*:||'; }

say "watching $REPO every ${EVERY}s"
while true; do
  want=$(latest)
  have=$(running)
  if [ -n "$want" ] && [ "$want" != "$have" ]; then
    say "wanted $want, running ${have:-nothing}: deploying"
    [ -z "$have" ] && $KUBECTL apply -f "$MANIFEST"
    $KUBECTL set image deploy/pipeline-demo app="$IMAGE:$want"
    if $KUBECTL rollout status deploy/pipeline-demo --timeout="${TIMEOUT}s"; then
      say "$want is live"
    else
      say "rollout of $want failed, the old copies keep serving"
    fi
  fi
  sleep "$EVERY"
done
