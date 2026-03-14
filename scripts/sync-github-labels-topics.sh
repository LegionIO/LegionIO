#!/usr/bin/env bash
set -euo pipefail

# sync-github-labels-topics.sh
#
# Applies standardized GitHub topics and issue labels across all LegionIO repos.
# Requires: gh CLI authenticated with repo admin access.
# Compatible with bash 3.2+ (macOS default).
#
# Usage:
#   ./scripts/sync-github-labels-topics.sh           # apply everything
#   ./scripts/sync-github-labels-topics.sh --dry-run  # preview without changes
#   ./scripts/sync-github-labels-topics.sh --labels    # labels only
#   ./scripts/sync-github-labels-topics.sh --topics    # topics only

ORG="LegionIO"
DRY_RUN=false
DO_LABELS=true
DO_TOPICS=true

for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=true ;;
    --labels)   DO_TOPICS=false ;;
    --topics)   DO_LABELS=false ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--labels] [--topics]"
      exit 0
      ;;
  esac
done

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# ─────────────────────────────────────────────────────────────────
# LABEL DEFINITIONS
# Each line: name|color|description
# ─────────────────────────────────────────────────────────────────

LABELS="
type:bug|d73a4a|Something isn't working
type:enhancement|a2eeef|New feature or improvement
type:docs|0075ca|Documentation only
type:chore|e4e669|Maintenance, deps, CI
type:breaking|b60205|Breaking change
priority:critical|b60205|Must fix immediately
priority:high|d93f0b|Next up
priority:medium|fbca04|Normal priority
priority:low|0e8a16|Nice to have
area:transport|c5def5|RabbitMQ / AMQP messaging
area:crypt|c5def5|Encryption, Vault, JWT
area:data|c5def5|Database / Sequel ORM
area:cache|c5def5|Redis / Memcached caching
area:settings|c5def5|Configuration management
area:logging|c5def5|Logging
area:json|c5def5|JSON serialization
area:cli|c5def5|CLI commands
area:api|c5def5|REST API
area:mcp|c5def5|MCP server
area:extensions|c5def5|Extension system / LEX
area:actors|c5def5|Actor execution modes
area:runners|c5def5|Runner functions
good first issue|7057ff|Good for newcomers
help wanted|008672|Extra attention needed
"

# default labels to remove (replaced by type: prefixed versions)
LABELS_TO_REMOVE="bug enhancement documentation duplicate invalid question wontfix"

# ─────────────────────────────────────────────────────────────────
# TOPIC DEFINITIONS
# ─────────────────────────────────────────────────────────────────

get_topics() {
  local repo="$1"
  local base="legionio,ruby"

  case "$repo" in
    # skip non-code repos
    .github|catalog)
      echo ""
      return
      ;;

    # framework
    LegionIO)
      echo "${base},legion-framework,legion-core,mcp,model-context-protocol,sinatra,cli,async"
      ;;

    # meta / org-level
    agentic-ai)
      echo "${base},ai,multi-agent"
      ;;
    Legion)
      echo "${base},legion-framework"
      ;;

    # core libraries
    legion-transport) echo "${base},legion-core,rabbitmq,amqp" ;;
    legion-crypt)     echo "${base},legion-core,vault,encryption,jwt" ;;
    legion-data)      echo "${base},legion-core,sequel,database" ;;
    legion-cache)     echo "${base},legion-core,redis,memcached,caching" ;;
    legion-json)      echo "${base},legion-core,json" ;;
    legion-logging)   echo "${base},legion-core,logging" ;;
    legion-settings)  echo "${base},legion-core,configuration" ;;
    legion-llm)       echo "${base},legion-core,ai,llm" ;;

    # built-in extensions
    lex-node)          echo "${base},legion-extension,legion-builtin,cluster,heartbeat" ;;
    lex-node_manager)  echo "${base},legion-extension,legion-builtin,cluster" ;;
    lex-tasker)        echo "${base},legion-extension,legion-builtin" ;;
    lex-conditioner)   echo "${base},legion-extension,legion-builtin" ;;
    lex-transformer)   echo "${base},legion-extension,legion-builtin" ;;
    lex-scheduler)     echo "${base},legion-extension,legion-builtin,cron,scheduling" ;;
    task_pruner)       echo "${base},legion-extension,legion-builtin" ;;
    lex-mesh)          echo "${base},legion-extension,legion-builtin,networking" ;;
    lex-swarm)         echo "${base},legion-extension,legion-builtin,multi-agent" ;;
    lex-swarm-github)  echo "${base},legion-extension,legion-builtin,multi-agent" ;;
    lex-memory)        echo "${base},legion-extension,legion-builtin,ai" ;;
    lex-emotion)       echo "${base},legion-extension,legion-builtin,ai" ;;
    lex-identity)      echo "${base},legion-extension,legion-builtin,identity,auth" ;;
    lex-trust)         echo "${base},legion-extension,legion-builtin,security" ;;
    lex-governance)    echo "${base},legion-extension,legion-builtin,governance" ;;
    lex-consent)       echo "${base},legion-extension,legion-builtin,security" ;;
    lex-prediction)    echo "${base},legion-extension,legion-builtin,ai" ;;
    lex-coldstart)     echo "${base},legion-extension,legion-builtin,ai" ;;
    lex-conflict)      echo "${base},legion-extension,legion-builtin,conflict-resolution" ;;
    lex-extinction)    echo "${base},legion-extension,legion-builtin,governance" ;;
    lex-tick)          echo "${base},legion-extension,legion-builtin,timing,clock" ;;
    lex-privatecore)   echo "${base},legion-extension,legion-builtin,security" ;;
    lex-lex)           echo "${base},legion-extension,legion-builtin" ;;

    # service extensions - notifications
    lex-slack)       echo "${base},legion-extension,notifications" ;;
    lex-pushbullet)  echo "${base},legion-extension,notifications" ;;
    lex-pushover)    echo "${base},legion-extension,notifications" ;;
    lex-smtp)        echo "${base},legion-extension,notifications" ;;
    lex-twilio)      echo "${base},legion-extension,notifications" ;;

    # service extensions - datastore
    lex-redis)              echo "${base},legion-extension,datastore" ;;
    lex-memcached)          echo "${base},legion-extension,datastore" ;;
    lex-elasticsearch)      echo "${base},legion-extension,datastore" ;;
    lex-elastic_app_search) echo "${base},legion-extension,datastore" ;;
    lex-influxdb)           echo "${base},legion-extension,datastore" ;;
    lex-s3)                 echo "${base},legion-extension,datastore" ;;

    # service extensions - monitoring
    lex-pagerduty) echo "${base},legion-extension,monitoring" ;;
    lex-ping)      echo "${base},legion-extension,monitoring" ;;
    lex-health)    echo "${base},legion-extension,monitoring" ;;
    lex-log)       echo "${base},legion-extension,monitoring" ;;

    # service extensions - ai
    lex-claude) echo "${base},legion-extension,ai" ;;
    lex-openai) echo "${base},legion-extension,ai" ;;
    lex-gemini) echo "${base},legion-extension,ai" ;;

    # service extensions - infrastructure
    lex-chef)   echo "${base},legion-extension,infrastructure" ;;
    lex-ssh)    echo "${base},legion-extension,infrastructure" ;;
    lex-http)   echo "${base},legion-extension,infrastructure" ;;
    lex-github) echo "${base},legion-extension,infrastructure" ;;
    lex-pihole) echo "${base},legion-extension,infrastructure" ;;

    # service extensions - productivity
    lex-todoist) echo "${base},legion-extension,productivity" ;;

    # service extensions - smart home
    lex-sonos)   echo "${base},legion-extension,smart-home" ;;
    lex-ecobee)  echo "${base},legion-extension,smart-home" ;;
    lex-esphome) echo "${base},legion-extension,smart-home" ;;
    lex-myq)     echo "${base},legion-extension,smart-home" ;;
    lex-sleepiq) echo "${base},legion-extension,smart-home" ;;
    lex-wled)    echo "${base},legion-extension,smart-home" ;;

    # catch-all for unknown lex-* repos
    lex-*)
      echo "${base},legion-extension"
      ;;

    # catch-all for unknown legion-* repos
    legion-*)
      echo "${base},legion-core"
      ;;

    *)
      echo "${base}"
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────
# APPLY LABELS
# ─────────────────────────────────────────────────────────────────

apply_labels() {
  local repo="$1"
  local full="${ORG}/${repo}"

  echo "  labels: syncing..."

  # fetch existing labels once
  local existing
  existing=$(gh label list --repo "$full" --json name --jq '.[].name' 2>/dev/null || true)

  # remove default labels that conflict with our type: labels
  for old_label in $LABELS_TO_REMOVE; do
    if echo "$existing" | grep -qx "$old_label"; then
      echo "    removing default label: $old_label"
      run gh label delete "$old_label" --repo "$full" --yes
    fi
  done

  # create or update our labels
  echo "$LABELS" | while IFS='|' read -r name color desc; do
    [ -z "$name" ] && continue

    if echo "$existing" | grep -qxF "$name"; then
      run gh label edit "$name" --repo "$full" --color "$color" --description "$desc"
    else
      echo "    creating label: $name"
      run gh label create "$name" --repo "$full" --color "$color" --description "$desc"
    fi
  done
}

# ─────────────────────────────────────────────────────────────────
# APPLY TOPICS
# ─────────────────────────────────────────────────────────────────

apply_topics() {
  local repo="$1"
  local full="${ORG}/${repo}"
  local topics
  topics=$(get_topics "$repo")

  if [ -z "$topics" ]; then
    echo "  topics: skipped (non-code repo)"
    return
  fi

  echo "  topics: ${topics}"
  run gh repo edit "$full" --add-topic "$topics"
}

# ─────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────

echo "Fetching repos from ${ORG}..."
REPOS=$(gh repo list "$ORG" --limit 200 --json name --jq '.[].name' | sort)
REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')

echo "Found ${REPO_COUNT} repos"
if [ "$DRY_RUN" = true ]; then
  echo "=== DRY RUN MODE ==="
fi
echo ""

for repo in $REPOS; do
  echo "[$repo]"

  if [ "$DO_TOPICS" = true ]; then
    apply_topics "$repo"
  fi

  if [ "$DO_LABELS" = true ]; then
    apply_labels "$repo"
  fi

  echo ""
done

echo "done."
