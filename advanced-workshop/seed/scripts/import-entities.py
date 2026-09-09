#!/usr/bin/env python3
import json
import os
import sys
import time
from getpass import getpass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# NOTE: Set your org credentials from the Port UI before running:
# export PORT_CLIENT_ID="your-client-id"
# export PORT_CLIENT_SECRET="your-client-secret"
# Optional (defaults to Port's EU region; set to https://api.us.port.io for the US region):
# export PORT_API_BASE_URL="https://api.port.io"

root = Path(__file__).resolve().parent.parent
entities_root = root / "entities"
blueprints_root = root / "blueprints"
actions_root = root / "actions"

client_id = os.getenv("PORT_CLIENT_ID")
client_secret = os.getenv("PORT_CLIENT_SECRET")
base_url = os.getenv("PORT_API_BASE_URL", "https://api.port.io").rstrip("/")

if not client_id:
    client_id = input("Enter PORT_CLIENT_ID: ").strip()
if not client_secret:
    client_secret = getpass("Enter PORT_CLIENT_SECRET: ").strip()

if not client_id or not client_secret:
    print("Missing credentials: provide PORT_CLIENT_ID and PORT_CLIENT_SECRET.", file=sys.stderr)
    sys.exit(1)

def http_json(method: str, url: str, body: dict | None = None, headers: dict | None = None):
    req_headers = {"Content-Type": "application/json"}
    if headers:
        req_headers.update(headers)
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = Request(url=url, data=data, method=method, headers=req_headers)
    with urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
        return resp.status, (json.loads(raw) if raw else {})

def iso_now_minus(hours: int, minutes: int = 0) -> str:
    ts = datetime.now(timezone.utc).replace(microsecond=0) - timedelta(hours=hours, minutes=minutes)
    return ts.isoformat().replace("+00:00", "Z")

def apply_relative_pr_dates(payload: dict, idx: int) -> dict:
    # Keep all PR datetime properties populated and within the last 48h.
    created_h = max(2, 47 - ((idx % 15) * 3) - (idx // 15))
    updated_h = max(1, created_h - 2)
    closed_h = max(0, updated_h - 1)
    merged_h = max(0, closed_h - 1)

    props = payload.setdefault("properties", {})
    props["createdAt"] = iso_now_minus(created_h, 10 + (idx % 40))
    props["updatedAt"] = iso_now_minus(updated_h, 15 + (idx % 35))
    props["closedAt"] = iso_now_minus(closed_h, 20 + (idx % 30))
    props["mergedAt"] = iso_now_minus(merged_h, 25 + (idx % 25))
    return payload

def apply_relative_deployment_dates(payload: dict, idx: int) -> dict:
    # Spread deployment timestamps across a realistic 48h release window.
    created_h = max(1, 47 - ((idx % 16) * 3) - (idx // 16))
    props = payload.setdefault("properties", {})
    props["createdAt"] = iso_now_minus(created_h, 12 + (idx % 45))
    return payload

def load_payloads(dir_path: Path):
    return sorted(dir_path.glob("*.json"), key=lambda p: p.name)

def maybe_request(method: str, url: str, body: dict | None = None, headers: dict | None = None):
    try:
        status, data = http_json(method, url, body=body, headers=headers)
        return status, data, None
    except HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return e.code, body, e
    except URLError as e:
        return None, str(e), e

try:
    _, auth_body = http_json(
        "POST",
        f"{base_url}/v1/auth/access_token",
        body={"clientId": client_id, "clientSecret": client_secret},
    )
except (HTTPError, URLError) as e:
    print(f"Auth failed: {e}", file=sys.stderr)
    sys.exit(1)

token = auth_body.get("accessToken")
if not token:
    print("Auth response missing accessToken.", file=sys.stderr)
    sys.exit(1)

auth_header = {"Authorization": f"Bearer {token}"}

# Reset matching blueprints if they already exist, then recreate from local files.
# Cleanup order removes dependent blueprints first.
cleanup_order = ["deployment", "incident", "pullRequest", "service", "repository"]
# Create order creates relation targets before dependents.
create_order = ["repository", "service", "pullRequest", "deployment", "incident"]

blueprint_files_by_id = {}
for bp_file in sorted(blueprints_root.glob("*.json"), key=lambda p: p.name):
    try:
        bp_payload = json.loads(bp_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        continue
    identifier = bp_payload.get("identifier")
    if identifier:
        blueprint_files_by_id[identifier] = bp_file

print("== Checking for pre-existing blueprints ==")
for blueprint in cleanup_order:
    check_status, _, check_err = maybe_request(
        "GET",
        f"{base_url}/v1/blueprints/{blueprint}",
        headers=auth_header,
    )
    if check_err or check_status == 404:
        print(f"[SKIP] {blueprint} blueprint does not exist.")
        continue
    if check_status != 200:
        print(f"[FAIL] Unable to check blueprint {blueprint} (HTTP {check_status}).", file=sys.stderr)
        sys.exit(1)

    print(f"[INFO] Existing blueprint found: {blueprint}. Deleting entities and blueprint.")
    del_entities_status, del_entities_data, del_entities_err = maybe_request(
        "DELETE",
        f"{base_url}/v1/blueprints/{blueprint}/all-entities",
        headers=auth_header,
    )
    if del_entities_err and del_entities_status not in (200, 404):
        print(f"[FAIL] Could not delete all entities for {blueprint} (HTTP {del_entities_status}) | {del_entities_data}", file=sys.stderr)
        sys.exit(1)
    if del_entities_status in (200, 404):
        print(f"[OK]   Cleared entities for {blueprint} (HTTP {del_entities_status}).")

    # Allow cascading deletion to settle before deleting the blueprint.
    time.sleep(1.0)
    del_bp_status, del_bp_data, del_bp_err = maybe_request(
        "DELETE",
        f"{base_url}/v1/blueprints/{blueprint}",
        headers=auth_header,
    )
    if del_bp_err and del_bp_status not in (200, 404):
        print(f"[FAIL] Could not delete blueprint {blueprint} (HTTP {del_bp_status}) | {del_bp_data}", file=sys.stderr)
        sys.exit(1)
    print(f"[OK]   Deleted blueprint {blueprint} (HTTP {del_bp_status}).")

print("\n== Recreating blueprints from local files ==")
for blueprint in create_order:
    bp_path = blueprint_files_by_id.get(blueprint)
    if not bp_path:
        print(f"[FAIL] Missing local blueprint file for identifier '{blueprint}'.", file=sys.stderr)
        sys.exit(1)
    payload = json.loads(bp_path.read_text(encoding="utf-8"))
    create_status, create_data, create_err = maybe_request(
        "POST",
        f"{base_url}/v1/blueprints",
        body=payload,
        headers=auth_header,
    )
    if create_err or create_status not in (200, 201):
        print(f"[FAIL] Could not create blueprint {blueprint} (HTTP {create_status}) | {create_data}", file=sys.stderr)
        sys.exit(1)
    print(f"[OK]   Created blueprint {blueprint}.")

print("\n== Upserting self-service actions from local files ==")
for action_file in sorted(actions_root.glob("*.json"), key=lambda p: p.name):
    payload = json.loads(action_file.read_text(encoding="utf-8"))
    action_identifier = payload.get("identifier")
    if not action_identifier:
        print(f"[FAIL] Action file {action_file.name} is missing 'identifier'.", file=sys.stderr)
        sys.exit(1)

    # Update if action exists, otherwise create it.
    upsert_status, upsert_data, upsert_err = maybe_request(
        "PUT",
        f"{base_url}/v1/actions/{action_identifier}",
        body=payload,
        headers=auth_header,
    )
    if upsert_status == 404:
        upsert_status, upsert_data, upsert_err = maybe_request(
            "POST",
            f"{base_url}/v1/actions",
            body=payload,
            headers=auth_header,
        )

    if upsert_err or upsert_status not in (200, 201):
        print(
            f"[FAIL] Could not upsert action {action_identifier} "
            f"(HTTP {upsert_status}) | {upsert_data}",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"[OK]   Upserted action {action_identifier}.")

import_plan = [
    ("repository", entities_root / "repositories"),
    ("service", entities_root / "services"),
    ("pullRequest", entities_root / "pull-requests"),
    ("deployment", entities_root / "deployments"),
]

failures = 0
for blueprint, folder in import_plan:
    files = load_payloads(folder)
    print(f"\n== Importing {blueprint} entities from {folder.name} ({len(files)}) ==")
    for idx, path in enumerate(files):
        payload = json.loads(path.read_text(encoding="utf-8"))

        if blueprint == "pullRequest":
            payload = apply_relative_pr_dates(payload, idx)
        elif blueprint == "deployment":
            payload = apply_relative_deployment_dates(payload, idx)

        url = f"{base_url}/v1/blueprints/{blueprint}/entities"
        try:
            status, _ = http_json("POST", url, body=payload, headers=auth_header)
            if status not in (200, 201):
                failures += 1
                print(f"[FAIL] {path.name} -> HTTP {status}")
            else:
                print(f"[OK]   {path.name}")
        except HTTPError as e:
            failures += 1
            body = e.read().decode("utf-8", errors="replace")
            print(f"[FAIL] {path.name} -> HTTP {e.code} | {body}")
        except URLError as e:
            failures += 1
            print(f"[FAIL] {path.name} -> Network error: {e}")

print("\nImport complete.")
if failures:
    print(f"Completed with {failures} failure(s).", file=sys.stderr)
    sys.exit(1)
print("All entities imported successfully.")
