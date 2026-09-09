# Seed Data

Pre-built blueprints, self-service action, agent prompts, and sample e-commerce data for the Advanced Workshop. Loading this is the first step of [Phase 1](../README.md#phase-1-ai-agents) — everything else in the workshop builds on it.

## What this provides

- SDLC entities (services, repositories, incidents, deployments, pull requests)
- An operational flow (incident creation) via a self-service action
- Agent-assisted response, standardized through prompts
- A structure ready to be populated with real per-team/per-environment entities

## Structure

- `blueprints/` — schema and relationship definitions
- `actions/` — self-service action definitions
- `agent-prompts/` — prompts for interactive AI agents (used in Phase 1)
- `ai-node-prompts/` — prompts for AI nodes inside automated workflows (used in Phase 3)
- `entities/` — sample entity instances, one folder per blueprint
- `scripts/` — import/provisioning utilities

## Components

### Blueprints

- `incident.json` — incident model with severity, status, event type, and remediation plan
- `service.json` — service blueprint
- `repository.json` — repository blueprint
- `deployment.json` — deployment blueprint with environment, date, and status
- `pull-request.json` — pull request blueprint with status, dates, link, and PR number

### Actions

- `create-incident.json` — self-service action to create incidents on the `incident` blueprint
  - Asks for event type, title, and impacted service
  - Initializes `status`, `event_type`, and `triggered_at`
  - Relates the incident to `affected_service`

### Agent prompts

Used with an interactive AI agent (a Port AI agent with a chat widget):

- `triage-prompt.md` — full-guardrail triage prompt. Determines severity by service tier, reviews deployments from the last 24h and related PRs, and identifies at-risk dependent services.
- `remediation-prompt.md` — guardrailed prompt for producing a remediation plan.

### AI node prompts

Used as instructions for AI nodes inside automated Port workflows:

- `triage-node.md` — concise triage prompt for a workflow AI node. Takes the incident identifier and determines severity from service tier plus deployments in the last 24h.
- `remediation-node.md` — concise remediation prompt for a workflow AI node. Takes the incident identifier and reviews service, deployments, PRs, and dependent services.

### Scripts

Both scripts are functionally identical — use whichever fits your environment:

- `scripts/import-entities.js` — Node.js version (recommended). No external dependencies; works on Windows, Linux, and Mac with Node.js installed.
- `scripts/import-entities.py` — Python 3 version. Standard library only, no pip packages.

Both scripts:
- Delete existing managed blueprints if present (`repository`, `service`, `pullRequest`, `deployment`, `incident`)
- Recreate blueprints from `blueprints/*.json`
- Upsert self-service actions from `actions/*.json` (including `create-incident.json`)
- Import sample entities in relation-safe order
- Recalculate relative timestamps for `pullRequest` and `deployment` on every run (up to 48h back), so the data always looks recent

## Current sample dataset

- `services`: 3
- `repositories`: 3
- `pull-requests`: 30
- `deployments`: 24

## Running the import

From the **workshop root** (not this `seed/` folder):

```bash
export PORT_CLIENT_ID="your-client-id"
export PORT_CLIENT_SECRET="your-client-secret"
# export PORT_API_BASE_URL="https://api.us.port.io"   # only if your account is on Port's US region

node seed/scripts/import-entities.js
# or:
python3 seed/scripts/import-entities.py
```

If the credentials aren't set as environment variables, the script will prompt for them interactively.

## Important notes

- **This is destructive** to the managed blueprints — it deletes and recreates them, including all of their entities. Don't point this at a Port account with data you care about.
- Entity relations are loaded in dependency-safe order to avoid relation errors.
- The incident-creation self-service action is included as part of setup — you don't need to build it, only use it (Phase 1) and then extend it with a workflow (Phases 2-3).
