#!/usr/bin/env bash
#
# check-completion.sh — verifies the Port Intro Workshop was completed.
#
# Calls the Port REST API directly with PORT_CLIENT_ID / PORT_CLIENT_SECRET
# and checks, programmatically, for the things each phase's Task asked for.
# It is NOT a judge of quality — a clean run means "the mechanical parts are
# there", not "your data model is well designed." See README.md for what
# this script deliberately does not (and, for AI agents, cannot) check.
#
# Usage:
#   export PORT_CLIENT_ID=...
#   export PORT_CLIENT_SECRET=...
#   [export PORT_API_BASE_URL=https://api.us.port.io]  # only if your account is on Port's US region
#   [export PORT_USER_EMAIL=you@example.com]           # optional, enables the team-membership check
#   ./check-completion.sh [--phase 1|2|3] [--verbose]
#
# Run with --phase N right after finishing that phase, as a checkpoint —
# it only runs that phase's checks instead of the whole workshop. Run with
# no --phase flag at the end to check everything at once.

set -uo pipefail

# Port's documented API base URLs: EU https://api.port.io, US https://api.us.port.io.
# Defaults to EU — override with PORT_API_BASE_URL if your workshop account is on the US cluster.
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

if [[ -n "$ONLY_PHASE" && "$ONLY_PHASE" != "1" && "$ONLY_PHASE" != "2" && "$ONLY_PHASE" != "3" ]]; then
  echo "--phase must be 1, 2, or 3 (got: $ONLY_PHASE)"
  exit 1
fi

run_phase() {
  # run_phase <N> -- true if phase N should run given --phase (or no flag = all)
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
  echo -e "${C_BOLD}Port Intro Workshop — Phase $ONLY_PHASE Checkpoint${C_RESET}"
else
  echo -e "${C_BOLD}Port Intro Workshop — Completion Check${C_RESET}"
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
  # Deliberately does NOT use jq's `//` for the .ok check: `//` treats `false`
  # the same as `null` (both count as "no value" in jq), so `.ok // "true"`
  # would always yield "true" even when .ok is a genuine `false` — silently
  # treating every real API error as success. Read .ok directly instead.
  local body="$1"
  [[ -n "$body" ]] || return 1
  jq -e . >/dev/null 2>&1 <<< "$body" || return 1
  [[ "$(jq -r '.ok' <<< "$body")" != "false" ]]
}

# ---- Phase 1: Blueprints and Relationships --------------------------------

if run_phase 1; then
  section "Phase 1: Blueprints and Relationships"

  BLUEPRINTS_RESPONSE=$(api_get "/v1/blueprints")

  if ! api_ok "$BLUEPRINTS_RESPONSE"; then
    fail "Could not list blueprints"
    verbose_dump "$BLUEPRINTS_RESPONSE"
    BLUEPRINTS_JSON='[]'
  else
    BLUEPRINTS_JSON=$(echo "$BLUEPRINTS_RESPONSE" | jq -c '.blueprints // []')
    if [[ "$BLUEPRINTS_JSON" == "[]" ]]; then
      warn "Response had no '.blueprints' array — Port's response shape may differ from what this script expects"
      verbose_dump "$BLUEPRINTS_RESPONSE"
    fi
  fi

  find_blueprint() {
    # find_blueprint <keyword-regex> -- prints the first matching identifier, or nothing
    echo "$BLUEPRINTS_JSON" | jq -r --arg re "$1" \
      '[.[] | select(((.identifier + " " + .title) | ascii_downcase) | test($re))][0].identifier // empty'
  }

  PR_ID=$(find_blueprint "pull.?request|^pr$")
  REPO_ID=$(find_blueprint "repo")
  JIRA_ID=$(find_blueprint "jira")

  BP_COUNT=$(echo "$BLUEPRINTS_JSON" | jq 'length')
  echo "  (found $BP_COUNT blueprint(s) in the account total)"

  check_blueprint() {
    local label="$1" id="$2"
    if [[ -z "$id" ]]; then
      fail "No blueprint found matching '$label' (by identifier/title)"
      return
    fi
    pass "Found a '$label' blueprint: $id"

    local props
    props=$(echo "$BLUEPRINTS_JSON" | jq --arg id "$id" '[.[] | select(.identifier == $id)][0].schema.properties | length')
    if [[ "$props" -ge 3 ]]; then
      pass "  '$id' has $props properties (>= 3)"
    else
      fail "  '$id' has only $props properties (need >= 3)"
    fi
  }

  check_blueprint "Pull Request" "$PR_ID"
  check_blueprint "Repository" "$REPO_ID"
  check_blueprint "Jira Ticket" "$JIRA_ID"

  RELATION_COUNT=$(echo "$BLUEPRINTS_JSON" | jq '[.[] | .relations | length] | add // 0')
  if [[ "$RELATION_COUNT" -ge 3 ]]; then
    pass "Found $RELATION_COUNT relation(s) across all blueprints (>= 3)"
  else
    fail "Found only $RELATION_COUNT relation(s) across all blueprints (need >= 3)"
  fi

  check_entities() {
    local label="$1" id="$2"
    [[ -z "$id" ]] && return
    local resp count
    resp=$(api_get "/v1/blueprints/$id/entities")
    if ! api_ok "$resp"; then
      fail "Could not list entities for '$id'"
      verbose_dump "$resp"
      return
    fi
    count=$(echo "$resp" | jq '.entities | length' 2>/dev/null || echo 0)
    if [[ "$count" -ge 3 ]]; then
      pass "'$label' ($id) has $count entities (>= 3)"
    else
      fail "'$label' ($id) has only $count entities (need >= 3)"
    fi
  }

  check_entities "Pull Request" "$PR_ID"
  check_entities "Repository" "$REPO_ID"
  check_entities "Jira Ticket" "$JIRA_ID"

  TEAMS_RESPONSE=$(api_get "/v1/teams")
  if ! api_ok "$TEAMS_RESPONSE"; then
    fail "Could not list teams"
    verbose_dump "$TEAMS_RESPONSE"
  else
    TEAM_COUNT=$(echo "$TEAMS_RESPONSE" | jq '.teams | length' 2>/dev/null || echo 0)
    if [[ "$TEAM_COUNT" -ge 1 ]]; then
      pass "Found $TEAM_COUNT team(s) in the account"
      if [[ -n "${PORT_USER_EMAIL:-}" ]]; then
        # .users elements may be plain email strings or {email:...} objects
        # depending on Port API version — handle both without erroring on type.
        IS_MEMBER=$(echo "$TEAMS_RESPONSE" | jq --arg email "$PORT_USER_EMAIL" \
          '[.teams[] | select(.users // [] | any((if type == "object" then (.email // "") else . end) == $email))] | length > 0')
        if [[ "$IS_MEMBER" == "true" ]]; then
          pass "$PORT_USER_EMAIL is a member of at least one team"
        else
          fail "$PORT_USER_EMAIL was not found as a member of any team"
        fi
      else
        warn "Set PORT_USER_EMAIL to also check that you're a member of a team (skipped)"
      fi
    else
      fail "No teams found — create one and add yourself as a member"
    fi
  fi
fi

# ---- Phase 2: Self-Service Actions ----------------------------------------

if run_phase 2; then
  section "Phase 2: Self-Service Actions"

  ACTIONS_RESPONSE=$(api_get "/v1/actions")
  if ! api_ok "$ACTIONS_RESPONSE"; then
    fail "Could not list actions"
    verbose_dump "$ACTIONS_RESPONSE"
  else
    ACTION_COUNT=$(echo "$ACTIONS_RESPONSE" | jq '.actions | length' 2>/dev/null || echo 0)
    if [[ "$ACTION_COUNT" -ge 2 ]]; then
      pass "Found $ACTION_COUNT action(s) (>= 2)"
    else
      fail "Found only $ACTION_COUNT action(s) (need >= 2: one Day 1, one Day 2)"
    fi
  fi
  MANUAL_CHECKS+=("That one action creates a new entity (Day 1) and another modifies an existing one (Day 2) — this script only counts actions, it doesn't inspect what each one does.")
  MANUAL_CHECKS+=("That each action's payload is actually dynamic (built from form inputs) and that you've run each one successfully at least once.")
fi

# ---- Phase 3: Dashboards and Agents ---------------------------------------

if run_phase 3; then
  section "Phase 3: Dashboards and Agents"

  PAGES_RESPONSE=$(api_get "/v1/pages")
  if ! api_ok "$PAGES_RESPONSE"; then
    fail "Could not list pages"
    verbose_dump "$PAGES_RESPONSE"
  else
    PAGES_JSON=$(echo "$PAGES_RESPONSE" | jq -c '.pages // []')
    PAGE_COUNT=$(echo "$PAGES_JSON" | jq 'length')
    DASHBOARD_WITH_WIDGETS=$(echo "$PAGES_JSON" | jq '[.[] | select((.widgets // []) | length > 0)] | length')

    if [[ "$PAGE_COUNT" -eq 0 ]]; then
      warn "No pages returned — Port's response shape may differ from what this script expects, or none exist yet"
      verbose_dump "$PAGES_RESPONSE"
    fi

    if [[ "$DASHBOARD_WITH_WIDGETS" -ge 1 ]]; then
      pass "Found $DASHBOARD_WITH_WIDGETS page(s) with at least one widget"
    else
      fail "No page found with any widgets — build the Phase 3 dashboard"
    fi
  fi

  MANUAL_CHECKS+=("That your dashboard's table widget is filtered/grouped meaningfully, and that the Actions widget is wired to your Phase 2 actions.")
  MANUAL_CHECKS+=("That an AI agent exists with a useful prompt and at least one tool attached. Port does not expose AI agents over the REST API this script uses, so this can only be confirmed by opening the Port UI yourself.")
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
