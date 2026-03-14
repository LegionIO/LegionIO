#!/usr/bin/env bash
set -uo pipefail

# rollout-ci-workflow.sh
#
# Replaces per-repo CI workflows with a call to the org-level reusable workflow.
# Commits and pushes to each repo.
#
# Usage:
#   ./scripts/rollout-ci-workflow.sh           # apply and push
#   ./scripts/rollout-ci-workflow.sh --dry-run  # preview without changes

LEGION_DIR="/Users/miverso2/rubymine/legion"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

# repos that need services
needs_rabbitmq="LegionIO legion-transport"
needs_redis="LegionIO legion-cache lex-redis"

get_workflow() {
  local name="$1"
  local rabbit=false
  local redis=false

  for r in $needs_rabbitmq; do [ "$r" = "$name" ] && rabbit=true; done
  for r in $needs_redis; do [ "$r" = "$name" ] && redis=true; done

  cat <<EOF
name: CI
on: [push, pull_request]
jobs:
  ci:
    uses: LegionIO/.github/.github/workflows/ci.yml@main
EOF

  if $rabbit || $redis; then
    echo "    with:"
    $rabbit && echo "      needs-rabbitmq: true"
    $redis && echo "      needs-redis: true"
  fi
}

count=0
skipped=0
errors=0

for dir in \
  "$LEGION_DIR"/LegionIO \
  "$LEGION_DIR"/legion-transport \
  "$LEGION_DIR"/legion-cache \
  "$LEGION_DIR"/legion-crypt \
  "$LEGION_DIR"/legion-data \
  "$LEGION_DIR"/legion-json \
  "$LEGION_DIR"/legion-logging \
  "$LEGION_DIR"/legion-settings \
  "$LEGION_DIR"/legion-llm \
  "$LEGION_DIR"/extensions-core/* \
  "$LEGION_DIR"/extensions-agentic/* \
  "$LEGION_DIR"/extensions-ai/* \
  "$LEGION_DIR"/extensions/lex-* \
  "$LEGION_DIR"/extensions-other/*; do

  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")

  workflow_content=$(get_workflow "$name")
  workflow_file="$dir/.github/workflows/ci.yml"

  # check if already using reusable workflow
  if [ -f "$workflow_file" ] && grep -q "LegionIO/.github/.github/workflows/ci.yml" "$workflow_file" 2>/dev/null; then
    echo "[$name] already using reusable workflow, skipping"
    skipped=$((skipped + 1))
    continue
  fi

  echo "[$name] updating ci.yml"

  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] would write:"
    echo "$workflow_content" | sed 's/^/    /'
    echo ""
    count=$((count + 1))
    continue
  fi

  mkdir -p "$dir/.github/workflows"
  echo "$workflow_content" > "$workflow_file"

  cd "$dir"

  # ensure correct git identity
  git_email=$(git config user.email 2>/dev/null || true)
  if [ "$git_email" != "matthewdiverson@gmail.com" ]; then
    git config user.name "Esity"
    git config user.email "matthewdiverson@gmail.com"
  fi

  git add .github/workflows/ci.yml
  if git diff --cached --quiet; then
    echo "  no changes, skipping"
    skipped=$((skipped + 1))
    continue
  fi

  git commit -m "switch to org-level reusable ci workflow" || { echo "  commit failed"; errors=$((errors + 1)); continue; }
  git push 2>&1 || { echo "  push failed"; errors=$((errors + 1)); continue; }

  echo "  done"
  count=$((count + 1))
  cd "$LEGION_DIR"
done

echo ""
echo "updated: $count | skipped: $skipped | errors: $errors"
