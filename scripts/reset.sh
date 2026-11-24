#!/usr/bin/env bash
# Put the demo back to its starting state for the next rehearsal.
#   scripts/reset.sh --dry-run   show what it would do
#   scripts/reset.sh             ask, then do it      (-y skips the question)
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=teerakarna/pipeline-demo
URL=${URL:-https://pipeline.kubernetic.io}
TOKEN_FILE=${TOKEN_FILE:-$HOME/.config/pipeline-demo/reset-token}
BASE=${BASE:-$(cat scripts/baseline-tag)}  # the release the demo starts from
DEMO=button-colour                    # the branch made live on stage
BROKEN=broken-tests                   # the pull request that stays open and red

DRY=; ASK=1
for a in "$@"; do case $a in --dry-run) DRY=1 ;; -y) ASK= ;; esac; done
say() { echo "-- $*"; }
run() { if [ -n "$DRY" ]; then echo "   [dry-run] $*"; else "$@"; fi; }
newer() { [ "$1" != "$BASE" ] && [ "$(printf '%s\n%s\n' "$BASE" "$1" | sort -V | tail -1)" = "$1" ]; }

git fetch -q origin --tags
BASE_SHA=$(git rev-parse -q --verify "refs/tags/$BASE^{commit}") || { echo "baseline tag $BASE not found"; exit 1; }
EXTRA=$(gh release list -R $REPO --json tagName --jq '.[].tagName' | while read -r t; do newer "$t" && echo "$t"; done || true)
DIRTY=; git diff --quiet "$BASE_SHA" origin/main -- app Dockerfile requirements.txt || DIRTY=1

say "baseline $BASE; releases to remove: ${EXTRA:-none}; code back to baseline: $([ -n "$DIRTY" ] && echo yes || echo no)"
if [ -z "$DRY" ] && [ -n "$ASK" ]; then read -r -p "Delete those releases, restore the code, reset votes? [y/N] " ok; [ "$ok" = y ]; fi

say "1/5 remove rehearsal releases (the Pi's loop rolls back by itself)"
for t in $EXTRA; do run gh release delete "$t" -R $REPO --cleanup-tag --yes; done

say "2/5 restore the code through a pull request (merged with [skip ci], so it makes no release)"
if [ -n "$DIRTY" ]; then
  B=restore-baseline-$(date +%s)
  run git switch -q -c "$B" origin/main
  run git checkout "$BASE_SHA" -- app Dockerfile requirements.txt
  run git commit -q -m "chore: restore the demo baseline"
  run git push -q -u origin "$B"
  if [ -z "$DRY" ]; then
    PR=$(gh pr create -R $REPO --base main --head "$B" --title "chore: restore the demo baseline" --body "Rehearsal reset." | grep -o '[0-9]*$')
    until gh pr checks "$PR" -R $REPO 2>&1 | grep -qE 'pass|fail'; do sleep 3; done
    gh pr checks "$PR" -R $REPO --watch >/dev/null
    gh pr merge "$PR" -R $REPO --squash --delete-branch --subject "chore: restore the demo baseline [skip ci] (#$PR)" --body ""
  fi
  run git switch -q main
  run git pull -q --ff-only origin main
fi

say "3/5 remove the demo branch and any pull request from it"
for pr in $(gh pr list -R $REPO --head $DEMO --state open --json number --jq '.[].number'); do run gh pr close "$pr" -R $REPO --delete-branch; done
run git push -q origin --delete $DEMO 2>/dev/null || true
run git branch -q -D $DEMO 2>/dev/null || true

say "4/5 make sure the failing pull request is open"
if [ -z "$(gh pr list -R $REPO --head $BROKEN --state open --json number --jq '.[].number')" ]; then
  run git switch -q -c $BROKEN origin/main
  run sed -i.bak 's/^BUTTON_COLOUR = .*/BUTTON_COLOUR = "pink"/' app/main.py
  run rm -f app/main.py.bak
  run git commit -q -am "feat: try a pink button"
  run git push -q --force origin $BROKEN
  run gh pr create -R $REPO --base main --head $BROKEN --title "feat: try a pink button" --body "The tests should catch this."
  run git switch -q main
  run git branch -q -D $BROKEN
fi

say "5/5 clear votes and counts, then check what is live"
if [ -r "$TOKEN_FILE" ]; then
  run curl -fsS -X POST -H "X-Reset-Token: $(cat "$TOKEN_FILE")" "$URL/admin/reset"; echo
else
  echo "   no token at $TOKEN_FILE: votes not cleared"
fi
[ -n "$DRY" ] || { echo -n "   live now: "; curl -fsS "$URL/api/status?cid=reset" || echo "not reachable"; echo; }
say "done. Board reset is not built yet."
