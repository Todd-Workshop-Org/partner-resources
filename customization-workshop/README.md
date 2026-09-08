# Port Ocean Custom Integration Workshop

A hands-on workshop for intermediate Port users. Everything runs in Kubernetes — you deploy a mock data source, deploy Port's `ocean-custom` integration container via Helm, then wire the two together entirely from the Port UI. No integration code to write.

For the follow-on exercise (building a custom dashboard plugin on top of the data this produces), see **[CUSTOM_PLUGIN_GUIDE.md](CUSTOM_PLUGIN_GUIDE.md)**.

---

## Contents

- [Architecture](#architecture)
- [The Mock Service](#the-mock-service)
- [Part 1: Setup](#part-1-setup)
- [Part 2: Deploy ocean-custom](#part-2-deploy-ocean-custom)
- [Part 3: Configure in the Port UI](#part-3-configure-in-the-port-ui)
- [Part 4: Verify](#part-4-verify)
- [Data Model Reference](#data-model-reference)
- [Troubleshooting](#troubleshooting)
- [Teardown](#teardown)

---

## Architecture

```
Kubernetes cluster — namespace: integrations
│
├─ mock-integration            (the "external system" you're integrating)
│    Service: mock-integration:5000
│    GET /api/services     → 5 services
│    GET /api/incidents    → 4 incidents
│
└─ ocean-custom               (port-labs/port-ocean Helm chart)
     Auth + host passed via --set at install time
     Endpoints + mapping configured in the Port UI
              │
              ▼
          Port.io catalog
              │
              ▼
       Custom UI plugin (optional — see CUSTOM_PLUGIN_GUIDE.md)
```

Helm receives auth, the integration type/identifier, and the **root host** (`baseUrl`) — the container needs to know that much just to boot. Everything under that host — which paths to poll, which blueprint each maps to, how fields become properties and relations — is configured in the Port UI, which is the point of the workshop.

---

## The Mock Service

A small Flask app that stands in for a real system (service registry, monitoring tool, incident manager). It requires no auth, so participants focus on integration concepts rather than credentials.

### `GET /api/services`

Returns 5 services. Query params: `team`, `status`.

```json
{
  "integration": "Port Mock Integration",
  "timestamp": "2026-08-18T00:11:21Z",
  "entity_type": "service",
  "entities": [
    {
      "id": "svc-api-gateway",
      "name": "API Gateway",
      "type": "service",
      "status": "healthy",
      "team": "Platform",
      "language": "Go",
      "repository": "https://github.com/example/api-gateway",
      "deployments": 1247,
      "uptime": 99.98,
      "last_deployment": "2026-08-17T22:11:21Z",
      "created_at": "2026-02-19T00:11:21Z",
      "tags": ["critical", "production", "platform"]
    }
  ],
  "metadata": { "total_count": 5, "source": "mock-integration", "version": "1.0" }
}
```

### `GET /api/incidents`

Returns 4 incidents. Query params: `severity`, `status`, `service_id`.

```json
{
  "entity_type": "incident",
  "entities": [
    {
      "id": "inc-2024-001",
      "title": "High latency in API Gateway",
      "description": "P1 incident: API response times elevated above threshold",
      "severity": "critical",
      "status": "investigating",
      "service_id": "svc-api-gateway",
      "team": "Platform",
      "created_at": "2026-08-17T23:11:21Z",
      "started_at": "2026-08-17T22:56:21Z",
      "assignee": "alice@example.com",
      "tags": ["performance", "incident"]
    }
  ]
}
```

`service_id` is the join key — you'll map it to a **relation**, not a property. That's the key data-modeling lesson of this workshop.

Both responses wrap their list in an envelope (`entities`, `metadata`, etc.) rather than returning a bare array. This matters later: each resource you configure in the Port UI needs its **Data Path** set to `.entities`, or every field mapping fails (see [Part 3](#32-add-resources-the-actual-endpoints)).

### Supporting endpoints

- `GET /health` — used by the K8s liveness/readiness probes
- `GET /api/docs` — self-describing endpoint list

---

## Part 1: Setup

### 1.1 Prerequisites

**Kubernetes cluster** — local is fine for a workshop:

```bash
# Docker Desktop: Preferences → Kubernetes → Enable Kubernetes
# or Minikube: minikube start
# or Kind: kind create cluster

kubectl cluster-info
```

**Helm 3:**

```bash
brew install helm      # macOS
# or: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm version
```

**Port account and credentials** — from Port.io → Settings → API:

```bash
export PORT_CLIENT_ID="your-client-id"
export PORT_CLIENT_SECRET="your-client-secret"
```

**Docker**, for building the mock service image:

```bash
docker --version
```

### 1.2 Add the Port Labs Helm Repo

```bash
helm repo add port-labs https://charts.port-labs.io
helm repo update
helm repo list | grep port-labs
```

### 1.3 Build the Mock Service Image

**Local cluster (Docker Desktop / Minikube):**

```bash
docker build -t port-mock-integration:latest .

# Minikube only — load the image into its Docker daemon:
minikube image load port-mock-integration:latest
# Docker Desktop's Kubernetes shares Docker's image cache already; no extra step needed.
```

**Cloud cluster (EKS / GKE / AKS):** push to a registry and update the image reference in `k8s-mock-service.yaml` accordingly:

```bash
docker build -t your-registry/port-mock-integration:latest .
docker push your-registry/port-mock-integration:latest
# then edit k8s-mock-service.yaml: image: your-registry/port-mock-integration:latest
```

### 1.4 Deploy the Mock Service

```bash
kubectl apply -f k8s-mock-service.yaml
kubectl rollout status deployment/mock-integration -n integrations --timeout=300s
kubectl get pods -n integrations
kubectl get svc -n integrations
```

This manifest also creates the `integrations` namespace — nothing else to create by hand.

### 1.5 Verify Connectivity

From inside the cluster (this is what `ocean-custom` will do later):

```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n integrations -- \
  curl -s http://mock-integration:5000/health
```

```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n integrations -- \
  curl -s http://mock-integration:5000/api/services
```

The second command should return 5 services. Optionally, from your own machine:

```bash
kubectl port-forward -n integrations svc/mock-integration 5000:5000 &
curl http://localhost:5000/api/services | jq '.entities | length'
pkill -f port-forward
```

### 1.6 Verify Port API Access

```bash
curl -X POST https://api.getport.io/v1/auth/access_token \
  -H "Content-Type: application/json" \
  -d "{\"clientId\": \"$PORT_CLIENT_ID\", \"clientSecret\": \"$PORT_CLIENT_SECRET\"}" \
  | jq '.accessToken'
```

Should return a token. A `401` means the credentials are wrong; recheck the env vars.

**Ready to continue once:**

- [ ] `kubectl get pods -n integrations` shows `mock-integration` `Running`
- [ ] The curl checks above returned real data
- [ ] The Port token request returned an `accessToken`

---

## Part 2: Deploy ocean-custom

```bash
helm install ocean-custom port-labs/port-ocean \
  --namespace integrations \
  --set port.clientId=$PORT_CLIENT_ID \
  --set port.clientSecret=$PORT_CLIENT_SECRET \
  --set integration.type=custom \
  --set integration.identifier=ocean-custom \
  --set integration.config.baseUrl=http://mock-integration.integrations.svc.cluster.local:5000 \
  --set integration.config.authType=none \
  --set integration.eventListener.type=POLLING
```

Note what's **not** here: no individual endpoint paths, no blueprint, no field mapping — just auth, an integration type/identifier, and a root host. That's deliberate; the rest is configured in the Port UI in Part 3.

Three of these values matter more than they look, because getting them wrong fails silently rather than with an obvious error:

- **`integration.type=custom`** — the chart builds the container image name from it (`ghcr.io/port-labs/port-ocean-{type}`). Leave it unset and Helm pulls the literal placeholder `port-ocean-default-type`, which doesn't exist → `ImagePullBackOff`.
- **`integration.config.baseUrl`** — the `custom` integration type is a generic REST poller; it needs to know the *root host* of the API it's polling before it can start at all. Omit it and the pod crashes on boot with `ValidationError: base_url — field required`, before it ever tries to reach Port.
- **`integration.eventListener.type=POLLING`** — the chart defaults to `KAFKA`, Port's real-time streaming listener, which requires your org to have Kafka credentials provisioned. Most orgs don't. Omit this and the pod authenticates fine, then dies with `KafkaCredentialsNotFound`. `POLLING` resyncs on an interval (default 60s) and needs no extra infra.

`authType=none` matches our mock service, which requires no credentials.

**Verify:**

```bash
kubectl get pods -n integrations
kubectl logs -n integrations -l app=mock-integration
kubectl logs -n integrations -l app.kubernetes.io/instance=ocean-custom -f
```

(Note the label selector: it's `app.kubernetes.io/instance=ocean-custom`, not `app=ocean-custom` — the chart's `app` label embeds the type/identifier and isn't stable across configs.)

---

## Part 3: Configure in the Port UI

### 3.1 Create Blueprints

Create both via the Port API rather than the UI form — faster, and repeatable.

**Get a token:**

```bash
PORT_TOKEN=$(curl -s -X POST "https://api.getport.io/v1/auth/access_token" \
  -H "Content-Type: application/json" \
  -d "{\"clientId\": \"$PORT_CLIENT_ID\", \"clientSecret\": \"$PORT_CLIENT_SECRET\"}" \
  | jq -r '.accessToken')
```

**Service blueprint:**

```bash
curl -s -X POST "https://api.getport.io/v1/blueprints" \
  -H "Authorization: Bearer $PORT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "service",
    "title": "Service",
    "icon": "Service",
    "schema": {
      "properties": {
        "status": { "type": "string", "title": "Status", "enum": ["healthy", "degraded", "down"] },
        "team": { "type": "string", "title": "Team" },
        "language": { "type": "string", "title": "Language" },
        "repository": { "type": "string", "title": "Repository", "format": "url" },
        "deployments": { "type": "number", "title": "Deployments" },
        "uptime": { "type": "number", "title": "Uptime %" },
        "last_deployment": { "type": "string", "title": "Last Deployment", "format": "date-time" },
        "tags": { "type": "string", "title": "Tags" }
      },
      "required": ["status", "team"]
    },
    "relations": {}
  }' | jq '.'
```

**Incident blueprint** (relation to Service — Service must exist first):

```bash
curl -s -X POST "https://api.getport.io/v1/blueprints" \
  -H "Authorization: Bearer $PORT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "incident",
    "title": "Incident",
    "icon": "Alert",
    "schema": {
      "properties": {
        "description": { "type": "string", "title": "Description" },
        "severity": { "type": "string", "title": "Severity", "enum": ["critical", "high", "medium", "low"] },
        "status": { "type": "string", "title": "Status", "enum": ["investigating", "resolved", "warning"] },
        "team": { "type": "string", "title": "Team" },
        "assignee": { "type": "string", "title": "Assignee" },
        "tags": { "type": "string", "title": "Tags" }
      },
      "required": ["severity", "status"]
    },
    "relations": {
      "service": { "title": "Service", "target": "service", "required": false, "many": false }
    }
  }' | jq '.'
```

**Verify both exist**:

```bash
curl -s "https://api.getport.io/v1/blueprints" -H "Authorization: Bearer $PORT_TOKEN" | jq '.blueprints[].identifier'
```

**Teardown / redo from scratch** (delete `incident` before `service` — Port won't delete a blueprint another one still relates to):

```bash
curl -s -X DELETE "https://api.getport.io/v1/blueprints/incident" -H "Authorization: Bearer $PORT_TOKEN"
curl -s -X DELETE "https://api.getport.io/v1/blueprints/service" -H "Authorization: Bearer $PORT_TOKEN"
```

### 3.2 Add Resources (the actual endpoints)

The Helm install only told the container its **root host** (`baseUrl`). Each individual endpoint — a `kind` — is added as a resource in the Port UI, as a path *relative to that root*.

**In the Port UI:** Integrations → **ocean-custom** → Configure / Resources → add one per endpoint:

**Resource 1 — Services**
- **Kind:** `/api/services` *(relative path, not the full URL)*
- **Blueprint:** Service
- **Selector:** default (`true`)
- **Data Path:** `.entities` — **required**, see below

**Resource 2 — Incidents**
- **Kind:** `/api/incidents`
- **Blueprint:** Incident
- **Selector:** default (`true`)
- **Data Path:** `.entities` — **required**, see below

The full request the container makes is `baseUrl + kind`, e.g. `http://mock-integration.integrations.svc.cluster.local:5000/api/services` — you never type that whole string, since the host half is already fixed.

**Why Data Path matters:** the mock service doesn't return a bare array, it wraps the list in an envelope (`{"entities": [...], "metadata": {...}}`). The container does **not** unwrap this automatically. **Data Path** is a JQ expression telling it where the array actually lives (Port's own field label is literally "Data Path" — "JQ path to extract data array from response," e.g. `.members`, `.data.items`). Leave it blank and the container maps fields against the whole envelope instead of an item inside it — since the envelope has no `.id`, every mapping fails:

```
[Transformation Layer] Mapping error for kind /api/incidents: identifier: jq misconfiguration detected for blueprint "incident" in fields: identifier (.id)
```

Set **Data Path** to `.entities` on both resources before mapping any fields.

### 3.3 Map Properties

Each resource's mapping form takes a JQ expression per field. Once Data Path has unwrapped the response, every mapping below is relative to a single item — `.id`, `.name`, etc. refer to one service/incident object, not the envelope.

**Service mapping:**

| Port field | JQ expression |
|-----------|---------------|
| identifier | `.id` |
| title | `.name` |
| property: status | `.status` |
| property: team | `.team` |
| property: language | `.language` |
| property: repository | `.repository` |
| property: deployments | `.deployments` |
| property: uptime | `.uptime` |
| property: last_deployment | `.last_deployment` |
| property: tags | `.tags \| join(",")` |

**Incident mapping:**

| Port field | JQ expression |
|-----------|---------------|
| identifier | `.id` |
| title | `.title` |
| property: description | `.description` |
| property: severity | `.severity` |
| property: status | `.status` |
| property: team | `.team` |
| property: assignee | `.assignee` |
| property: tags | `.tags \| join(",")` |
| **relation: service** | `.service_id` |

`.service_id` goes in the **relation** field, not a property field — that's the one mapping mistake that catches everyone at least once.

### 3.4 Sync

In the Port UI: Integrations → **ocean-custom** → **Run Now**. Check the sync log for errors, then check the catalog.

Optionally set a sync schedule (Integrations → ocean-custom → Sync Frequency: manual / every 15 min / hourly / custom) once manual runs are working.

---

## Part 4: Verify

**In the Port catalog:**

- 5 Services, 4 Incidents should appear
- Open a Service — all properties should be populated
- Open an Incident — it should show a **Relates to Service** link; clicking it should land on the correct Service

---

## Data Model Reference

**Service** blueprint

| Property | Type | Source field |
|----------|------|--------------|
| identifier | key | `id` |
| title | string | `name` |
| status | enum (healthy/degraded/down) | `status` |
| team | string | `team` |
| language | string | `language` |
| repository | url | `repository` |
| deployments | number | `deployments` |
| uptime | number | `uptime` |
| last_deployment | date-time | `last_deployment` |
| tags | string | `tags` (array → joined) |

**Incident** blueprint

| Property | Type | Source field |
|----------|------|--------------|
| identifier | key | `id` |
| title | string | `title` |
| description | string | `description` |
| severity | enum (critical/high/medium/low) | `severity` |
| status | enum (investigating/resolved/warning) | `status` |
| team | string | `team` |
| assignee | string | `assignee` |
| tags | string | `tags` (array → joined) |
| **service** | **relation → Service** | **`service_id`** |

---

## Troubleshooting

### ocean-custom pod won't come up

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImagePullBackOff`, image name contains `default-type` | `integration.type=custom` missing from `helm install` | Reinstall with it set |
| Pod `Running` but restarting, logs end in `ValidationError: base_url — field required` | `integration.config.baseUrl` missing | Reinstall with it set |
| Pod authenticates fine, then `Exception: No kafka credentials found` | `integration.eventListener.type` defaulted to `KAFKA`; org isn't provisioned for it | Reinstall with `--set integration.eventListener.type=POLLING` |
| Repeated `401` on `POST .../auth/access_token` | Wrong `port.clientId` / `port.clientSecret` | Recheck exported env vars |

Each of these needs a fresh `helm upgrade` (or uninstall/reinstall) with the missing `--set` added — the running pod won't self-correct.

### Mock service issues

| Symptom | Check |
|---------|-------|
| Mock pod `ImagePullBackOff` | Image not in the cluster — rebuild, and for Minikube run `minikube image load port-mock-integration:latest` (manifest uses `imagePullPolicy: Never` for local images) |
| Pod won't start | `kubectl describe pod -n integrations -l app=mock-integration`; check for resource limits or a port conflict |
| Can't connect | `kubectl get svc,endpoints -n integrations`; try the port-forward test in [1.5](#15-verify-connectivity) |

### Data not appearing in Port

1. Both pods running? `kubectl get pods -n integrations`
2. Blueprints actually created? `curl .../v1/blueprints` check from [3.1](#31-create-blueprints)
3. Resource `kind` set to the **relative path** (`/api/services`), not the full URL — a full URL double-prefixes onto `baseUrl` and 404s
4. **Data Path** set to `.entities` on both resources — the single most common blocker; symptom is `jq misconfiguration detected ... identifier (.id)` in the sync log
5. `.service_id` mapped into the **relation** field, not a property — symptom is incidents appear but with no linked service
6. `kubectl logs -n integrations -l app.kubernetes.io/instance=ocean-custom -f`
7. Trigger a manual **Run Now** in the Port UI and re-check the sync log

---

## Teardown

```bash
helm uninstall ocean-custom -n integrations
kubectl delete -f k8s-mock-service.yaml
```

## Modifying the Mock Data

Edit `app/main.py` (`generate_services()` / `generate_incidents()`), then:

```bash
docker build -t port-mock-integration:latest . && kubectl rollout restart deployment/mock-integration -n integrations
```

---

### Advanced Concepts

- Add query params to a resource (`?severity=critical`) and observe the filtered sync
- Add a second relation or a computed property
- Edit the mock data and re-sync (see [Modifying the Mock Data](#modifying-the-mock-data))

---

## Resources

- [Ocean custom integration docs](https://docs.port.io/context-lake/ingestion/ingest-data-into-port/custom-integration/ocean-custom-integration/overview/)
- [Port documentation](https://docs.port.io)
- [Port community Slack](https://slack.getport.io)
