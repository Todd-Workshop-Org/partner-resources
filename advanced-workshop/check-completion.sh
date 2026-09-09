#!/usr/bin/env bash
#
# check-completion.sh — verifies the Advanced Workshop (AI Agents & Agentic
# Workflows) was completed.
#
# Calls the Port REST API directly with PORT_CLIENT_ID / PORT_CLIENT_SECRET.
# It is NOT a judge of quality, and it CANNOT see AI agents, workflows, or
# their run history at all — Port doesn't expose those over this API. What
# it checks instead is the observable *effect* of each phase: specific
# property values on incident entities that only get set if the
# corresponding workflow node actually ran. See README.md for the full
# list of what each checkpoint does and doesn't confirm.
#
# Usage:
#   export PORT_CLIENT_ID=...
#   export PORT_CLIENT_SECRET=...
#   [export PORT_API_BASE_URL=https://api.us.port.io]  # only if your account is on Port's US region
#   ./check-completion.sh [--phase setup|1|2|3] [--verbose]
#
# Run with --phase right after finishing that phase, as a checkpoint — it
# only runs that phase's checks. Run with no --phase flag at the end for
# the full picture.

set -uo pipefail

# Port's documented API base URLs: EU https://api.port.io, US https://api.us.port.io.
API_BASE="${PORT_API_BASE_URL:-https://api.port.io}"
VERBOSE=0
ONLY_PHASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose|-v) VERBOSE=1; shift ;;
    --phase) ONLY_PHASE="${2:-}"; shift 2 ;;
    --phase=*) ONLY_PHASE="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -n "$ONLY_PHASE" && "$ONLY_PHASE" != "setup" && "$ONLY_PHASE" != "1" && "$ONLY_PHASE" != "2" && "$ONLY_PHASE" != "3" ]]; then
  echo "--phase must be setup, 1, 2, or 3 (got: $ONLY_PHASE)"
  exit 1
fi

run_phase() {
  # run_phase <name> -- true if that phase should run given --phase (or no flag = all)
  [[ -z "$ONLY_PHASE" || "$ONLY_PHASE" == "$1" ]]
}

PASS=0
FAIL=0
WARN=0
MANUAL_CHECKS=()

# ---- output helpers -------------------------------------------------------

if [[ -t 1 ]]; then
  C_GREEN='\033[0;32m'; C_RED='\033[0;31m'; C_YELLOW='\033[0;33m'; C_BOLD='\033[1m'; C_RESET='\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_BOLD=''; C_RESET=''
fi

pass() { echo -e "  ${C_GREEN}✓${C_RESET} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${C_RED}✗${C_RESET} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${C_YELLOW}!${C_RESET} $1"; WARN=$((WARN+1)); }
section() { echo; echo -e "${C_BOLD}$1${C_RESET}"; }
verbose_dump() { [[ $VERBOSE -eq 1 ]] && echo "    raw response: $1" >&2; }

# ---- prerequisites ---------------------------------------------------------

command -v curl >/dev/null 2>&1 || { echo "curl is required and not on PATH"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "jq is required and not on PATH"; exit 1; }

if [[ -z "${PORT_CLIENT_ID:-}" || -z "${PORT_CLIENT_SECRET:-}" ]]; then
  echo "PORT_CLIENT_ID and PORT_CLIENT_SECRET must both be set. See README.md Prerequisites."
  exit 1
fi

if [[ -n "$ONLY_PHASE" ]]; then
  echo -e "${C_BOLD}Advanced Workshop — Phase $ONLY_PHASE Checkpoint${C_RESET}"
else
  echo -e "${C_BOLD}Advanced Workshop — Completion Check${C_RESET}"
fi

# ---- auth -------------------------------------------------------------------

section "Authentication"

AUTH_RESPONSE=$(curl -s -X POST "$API_BASE/v1/auth/access_token" \
  -H "Content-Type: application/json" \
  -d "{\"clientId\": \"$PORT_CLIENT_ID\", \"clientSecret\": \"$PORT_CLIENT_SECRET\"}")

PORT_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.accessToken // empty')

if [[ -z "$PORT_TOKEN" ]]; then
  fail "Could not get an access token — check PORT_CLIENT_ID / PORT_CLIENT_SECRET"
  verbose_dump "$AUTH_RESPONSE"
  echo
  echo "Cannot continue without a token. Exiting."
  exit 1
fi
pass "Authenticated to Port"

api_get() {
  # api_get <path>  -- returns raw JSON body on stdout
  curl -s "$API_BASE$1" -H "Authorization: Bearer $PORT_TOKEN"
}

api_ok() {
  # api_ok <json>  -- true if the response is valid JSON and doesn't look like a Port error.
  # Deliberately reads .ok directly rather than via jq's `//`: `//` treats
  # `false` the same as `null` (both count as "no value"), so `.ok // "true"`
  # would always yield "true" even when .ok is a genuine `false`.
  local body="$1"
  [[ -n "$body" ]] || return 1
  jq -e . >/dev/null 2>&1 <<< "$body" || return 1
  [[ "$(jq -r '.ok' <<< "$body")" != "false" ]]
}

get_entities() {
  # get_entities <blueprint> -- prints the entities array (JSON), or [] on error
  local resp
  resp=$(api_get "/v1/blueprints/$1/entities")
  if ! api_ok "$resp"; then
    verbose_dump "$resp"
    echo '[]'
    return 1
  fi
  jq -c '.entities // []' <<< "$resp"
}

# ---- Setup: seed data -------------------------------------------------------

if run_phase setup; then
  section "Setup: Seed Data"

  BLUEPRINTS_RESPONSE=$(api_get "/v1/blueprints")
  if ! api_ok "$BLUEPRINTS_RESPONSE"; then
    fail "Could not list blueprints"
    verbose_dump "$BLUEPRINTS_RESPONSE"
    BLUEPRINTS_JSON='[]'
  else
    BLUEPRINTS_JSON=$(jq -c '.blueprints // []' <<< "$BLUEPRINTS_RESPONSE")
    if [[ "$BLUEPRINTS_JSON" == "[]" ]]; then
      warn "Response had no '.blueprints' array — Port's response shape may differ from what this script expects, or you simply have zero blueprints"
      verbose_dump "$BLUEPRINTS_RESPONSE"
    fi
  fi

  blueprint_exists() {
    jq -e --arg id "$1" 'any(.[]; .identifier == $id)' <<< "$BLUEPRINTS_JSON" >/dev/null 2>&1
  }

  check_seed_blueprint() {
    local id="$1" min_entities="$2"
    if ! blueprint_exists "$id"; then
      fail "Blueprint '$id' not found — run the seed import (see Setup in README.md)"
      return
    fi
    pass "Blueprint '$id' exists"

    local entities count
    entities=$(get_entities "$id")
    count=$(jq 'length' <<< "$entities")
    if [[ "$count" -ge "$min_entities" ]]; then
      pass "  '$id' has $count entities (>= $min_entities)"
    else
      fail "  '$id' has only $count entities (expected >= $min_entities from the seed dataset)"
    fi
  }

  check_seed_blueprint "service" 3
  check_seed_blueprint "repository" 3
  check_seed_blueprint "pullRequest" 20
  check_seed_blueprint "deployment" 20
  check_seed_blueprint "incident" 0

  ACTIONS_RESPONSE=$(api_get "/v1/actions")
  if api_ok "$ACTIONS_RESPONSE"; then
    HAS_ACTION=$(jq '[.actions // [] | .[] | select(.identifier == "create_workflow_incident")] | length > 0' <<< "$ACTIONS_RESPONSE")
    if [[ "$HAS_ACTION" == "true" ]]; then
      pass "'Create Workflow Incident' self-service action exists"
    else
      fail "'Create Workflow Incident' action not found — run the seed import"
    fi
  else
    fail "Could not list actions"
    verbose_dump "$ACTIONS_RESPONSE"
  fi
fi

# ---- Phase 1: AI Agents -----------------------------------------------------

if run_phase 1; then
  section "Phase 1: AI Agents"

  INCIDENTS=$(get_entities "incident")
  INCIDENT_COUNT=$(jq 'length' <<< "$INCIDENTS")

  if [[ "$INCIDENT_COUNT" -ge 1 ]]; then
    pass "Found $INCIDENT_COUNT incident entity(ies) — the self-service action has been used"
  else
    fail "No incident entities found — create one with the 'Create Workflow Incident' action"
  fi

  MANUAL_CHECKS+=("That two AI agents exist (Triage, Remediation), each using the intended prompt from seed/agent-prompts/.")
  MANUAL_CHECKS+=("That each agent has conversation starters and a working chat widget on a dashboard. Port does not expose agents over the REST API this script uses, so this can only be confirmed by opening the Port UI yourself.")
  MANUAL_CHECKS+=("That you actually ran the Triage Agent from its widget and read real output, not just that the widget renders.")
fi

# ---- Phase 2: Workflows ------------------------------------------------------

if run_phase 2; then
  section "Phase 2: Workflows"

  INCIDENTS=$(get_entities "incident")
  ACKNOWLEDGED=$(jq '[.[] | select(.properties.status == "acknowledged" and .properties.incident_owner == "Port AI")] | length' <<< "$INCIDENTS")

  if [[ "$ACKNOWLEDGED" -ge 1 ]]; then
    pass "Found $ACKNOWLEDGED incident(s) with status=acknowledged and incident_owner=\"Port AI\" — Nodes 1+2 ran successfully"
  else
    fail "No incident has status=acknowledged with incident_owner=\"Port AI\" yet — create a new incident via the self-service action to trigger the workflow, then re-check"
  fi

  MANUAL_CHECKS+=("That the Control Flow node (Node 3) correctly branches on event_type — check the workflow's run history in the Port UI with one incident of each event_type.")
fi

# ---- Phase 3: Agentic Workflow -----------------------------------------------

if run_phase 3; then
  section "Phase 3: Agentic Workflow"

  INCIDENTS=$(get_entities "incident")
  TRIAGED=$(jq '[.[] | select((.properties.incident_triage // "") != "")] | length' <<< "$INCIDENTS")
  REMEDIATED=$(jq '[.[] | select((.properties.remediation_plan // "") != "")] | length' <<< "$INCIDENTS")

  if [[ "$TRIAGED" -ge 1 ]]; then
    pass "Found $TRIAGED incident(s) with incident_triage populated — the Triage Agent branch (Nodes 4+5) ran"
  else
    fail "No incident has incident_triage populated yet — trigger the triage branch and re-check"
  fi

  if [[ "$REMEDIATED" -ge 1 ]]; then
    pass "Found $REMEDIATED incident(s) with remediation_plan populated — the Remediation Agent branch (Nodes 6+7) ran"
  else
    fail "No incident has remediation_plan populated yet — trigger the remediation branch and re-check"
  fi

  MANUAL_CHECKS+=("That the actual triage and remediation text is coherent and useful — read a couple of incidents, don't just trust that the field is non-empty.")
fi

# ---- Summary ----------------------------------------------------------------

section "Summary"
echo -e "  ${C_GREEN}$PASS passed${C_RESET}, ${C_RED}$FAIL failed${C_RESET}, ${C_YELLOW}$WARN warning(s)${C_RESET}"

if [[ ${#MANUAL_CHECKS[@]} -gt 0 ]]; then
  echo
  echo "Not verifiable by this script — confirm these yourself:"
  for item in "${MANUAL_CHECKS[@]}"; do
    echo "  • $item"
  done
fi

echo
if [[ $FAIL -eq 0 ]]; then
  if [[ -n "$ONLY_PHASE" ]]; then
    echo -e "${C_GREEN}Phase $ONLY_PHASE checks passed.${C_RESET} Review any manual checks above, then move on."
  else
    echo -e "${C_GREEN}All automated checks passed.${C_RESET} Review the manual checks above, then you're done."
  fi
  exit 0
else
  echo -e "${C_RED}$FAIL check(s) failed.${C_RESET} Re-read the relevant phase in README.md and try again."
  echo "Run with --verbose to see the raw API responses behind any failed or warned check."
  exit 1
fi
