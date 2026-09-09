# Entities Seed Data

This folder contains realistic sample entities for the project blueprints:

- `service`
- `repository`
- `pullRequest`
- `deployment`

All JSON files use an API-compatible body shape for Port entity creation:

- `identifier`
- `title`
- `properties`
- `relations`

## Recommended import order

To avoid relation resolution issues, import entities in this order:

1. `repositories/`
2. `services/` (references repositories)
3. `pull-requests/` (references repositories)
4. `deployments/` (references services and pull requests)

## Suggested API pattern

Use Port's entity endpoint per blueprint:

- `POST /v1/blueprints/repository/entities`
- `POST /v1/blueprints/service/entities`
- `POST /v1/blueprints/pullRequest/entities`
- `POST /v1/blueprints/deployment/entities`

Example body (from any file in this folder):

```json
{
  "identifier": "svc-checkout-api",
  "title": "Checkout API",
  "properties": {
    "tier": "Tier 1"
  },
  "relations": {
    "repo": "repo-checkout-api"
  }
}
```

## Current dataset size

- `services`: 3
- `repositories`: 3
- `pull-requests`: 30
- `deployments`: 24

## Import script

Use `scripts/import-entities.py` to import all entities in dependency-safe order.

Before running, export your Port org credentials from the Port UI:

- `PORT_CLIENT_ID`
- `PORT_CLIENT_SECRET`

Behavior note: the script recalculates relative timestamps for `pull-requests` and
`deployments` on each run, keeping those dates realistic and within the last 48 hours.

Reset note: at startup, the script checks for pre-existing blueprints with matching
identifiers (`repository`, `service`, `pullRequest`, `deployment`), removes them if
present (including all entities), recreates blueprints from local `blueprints/*.json`,
and then imports the seed entities.

