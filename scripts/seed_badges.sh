#!/usr/bin/env bash
# Bootstrap the `badges` branch on `origin` so the shields-endpoint badges
# in README.md render before CI has run on main.
#
# Runs all three test layers locally, builds the JSON files shields.io reads,
# and force-pushes them to a fresh orphan `badges` branch.
#
# Usage:   bash scripts/seed_badges.sh                  # builds + pushes to $REMOTE
#          REMOTE=origin bash scripts/seed_badges.sh    # pick a different remote
#          DRY_RUN=1 bash scripts/seed_badges.sh        # builds, prints, no push
#
# Defaults to remote `rabarbra` if it exists, else `origin`. The README's
# shields-endpoint URLs must point at the same GitHub repo as the remote you
# push to here, otherwise shields will 404.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] \
    || { echo "not in a git repo" >&2; exit 2; }

if [ -z "${REMOTE:-}" ]; then
    if git remote get-url rabarbra >/dev/null 2>&1; then
        REMOTE=rabarbra
    else
        REMOTE=origin
    fi
fi
git remote get-url "$REMOTE" >/dev/null 2>&1 \
    || { echo "remote '$REMOTE' not found; pick another with REMOTE=<name>" >&2; exit 2; }

if [ -n "$(git status --porcelain)" ]; then
    echo "working tree not clean — commit or stash first" >&2
    exit 2
fi

run_layer() {
    local name="$1" cmd="$2" parser="$3"
    echo ">> $name"
    rc=0
    "$cmd" 2>&1 | tee "/tmp/seed_${name}.log" || rc=$?
    eval "$parser /tmp/seed_${name}.log"
    if [ "$rc" -ne 0 ]; then
        echo "$name failed (rc=$rc) — seeded badge will reflect that" >&2
    fi
}

# --- run tests, capture passed/total ---

make test-unit 2>&1 | tee /tmp/seed_unit.log || true
line=$(grep -Eo '[0-9]+ pass(ed)?( \([0-9]+ total\))?' /tmp/seed_unit.log | tail -1 || true)
U_PASS=$(echo "$line" | awk '{print $1}'); : "${U_PASS:=0}"
U_TOTAL=$(echo "$line" | grep -Eo '[0-9]+ total' | awk '{print $1}'); : "${U_TOTAL:=$U_PASS}"

make test-kernel 2>&1 | tee /tmp/seed_kernel.log || true
line=$(grep -Eo 'summary: [0-9]+ passed, [0-9]+ failed' /tmp/seed_kernel.log | tail -1 || true)
K_PASS=$(echo "$line" | awk '{print $2}'); : "${K_PASS:=0}"
K_FAIL=$(echo "$line" | awk '{print $4}'); : "${K_FAIL:=0}"
K_TOTAL=$(( K_PASS + K_FAIL ))

make test-integration 2>&1 | tee /tmp/seed_integration.log || true
line=$(grep -Eo 'summary: [0-9]+ passed, [0-9]+ failed' /tmp/seed_integration.log | tail -1 || true)
I_PASS=$(echo "$line" | awk '{print $2}'); : "${I_PASS:=0}"
I_FAIL=$(echo "$line" | awk '{print $4}'); : "${I_FAIL:=0}"
I_TOTAL=$(( I_PASS + I_FAIL ))

echo
echo "results: unit=$U_PASS/$U_TOTAL  kernel=$K_PASS/$K_TOTAL  integration=$I_PASS/$I_TOTAL"

color() {
    if [ "$1" = "$2" ] && [ "$1" != "0" ]; then echo brightgreen
    elif [ "$1" = "0" ]; then echo red
    else echo yellow; fi
}
mk() {
    cat <<EOF
{
  "schemaVersion": 1,
  "label": "$1",
  "message": "$2 / $3",
  "color": "$(color "$2" "$3")"
}
EOF
}

tmp="$(mktemp -d)"
mk "unit tests"        "$U_PASS" "$U_TOTAL" >"$tmp/unit.json"
mk "kernel tests"      "$K_PASS" "$K_TOTAL" >"$tmp/kernel.json"
mk "integration tests" "$I_PASS" "$I_TOTAL" >"$tmp/integration.json"

if [ "${DRY_RUN:-0}" = "1" ]; then
    echo
    echo "--- generated JSONs (not pushed; DRY_RUN=1) ---"
    for f in "$tmp"/*.json; do echo; echo "# $(basename "$f")"; cat "$f"; done
    exit 0
fi

# Save current branch so we restore it.
ORIG_REF="$(git rev-parse --abbrev-ref HEAD)"
trap 'git checkout -- . 2>/dev/null || true; git checkout "$ORIG_REF" 2>/dev/null || true; rm -rf "$tmp"' EXIT

git checkout --orphan badges
git rm -rf --quiet . || true
mv "$tmp"/*.json .
git add unit.json kernel.json integration.json
git commit -m "badges: seed $(date -u +%Y-%m-%dT%H:%M:%SZ)" --quiet

echo
echo ">> pushing badges branch to $REMOTE (force)"
git push "$REMOTE" badges --force

echo "done — README badges should render after a few seconds."
