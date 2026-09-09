#!/usr/bin/env node
// NOTE: Set your org credentials from the Port UI before running:
//   export PORT_CLIENT_ID="your-client-id"      (Mac/Linux)
//   export PORT_CLIENT_SECRET="your-secret"
//   set PORT_CLIENT_ID=your-client-id            (Windows cmd)
//   $env:PORT_CLIENT_ID="your-client-id"         (Windows PowerShell)

"use strict";
const https = require("https");
const http = require("http");
const fs = require("fs");
const path = require("path");
const readline = require("readline");

const root = path.resolve(__dirname, "..");
const entitiesRoot = path.join(root, "entities");
const blueprintsRoot = path.join(root, "blueprints");
const actionsRoot = path.join(root, "actions");

function httpJson(method, url, body, headers) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const lib = parsed.protocol === "https:" ? https : http;
    const data = body !== undefined ? JSON.stringify(body) : undefined;
    const reqHeaders = { "Content-Type": "application/json", ...headers };
    if (data) reqHeaders["Content-Length"] = Buffer.byteLength(data);

    const req = lib.request(
      { hostname: parsed.hostname, port: parsed.port, path: parsed.pathname + parsed.search, method, headers: reqHeaders },
      (res) => {
        let raw = "";
        res.on("data", (chunk) => (raw += chunk));
        res.on("end", () => {
          if (res.statusCode >= 400) {
            const err = new Error(`HTTP ${res.statusCode}`);
            err.status = res.statusCode;
            err.body = raw;
            return reject(err);
          }
          resolve({ status: res.statusCode, data: raw ? JSON.parse(raw) : {} });
        });
      }
    );
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

async function maybeRequest(method, url, body, headers) {
  try {
    const { status, data } = await httpJson(method, url, body, headers);
    return { status, data, err: null };
  } catch (e) {
    return { status: e.status ?? null, data: e.body ?? String(e), err: e };
  }
}

function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (ans) => { rl.close(); resolve(ans.trim()); }));
}

function promptSecret(question) {
  // Plain readline — works on Windows cmd, PowerShell, Mac, and Linux.
  // The secret will be visible while typing; set PORT_CLIENT_SECRET as an
  // env var before running if you prefer it never appears on screen.
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (ans) => { rl.close(); resolve(ans.trim()); }));
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function isoNowMinus(hours, minutes = 0) {
  const ts = new Date(Date.now() - (hours * 3600 + minutes * 60) * 1000);
  ts.setMilliseconds(0);
  return ts.toISOString().replace(".000Z", "Z");
}

function applyRelativePrDates(payload, idx) {
  const createdH = Math.max(2, 47 - ((idx % 15) * 3) - Math.floor(idx / 15));
  const updatedH = Math.max(1, createdH - 2);
  const closedH = Math.max(0, updatedH - 1);
  const mergedH = Math.max(0, closedH - 1);
  const props = payload.properties ?? (payload.properties = {});
  props.createdAt = isoNowMinus(createdH, 10 + (idx % 40));
  props.updatedAt = isoNowMinus(updatedH, 15 + (idx % 35));
  props.closedAt  = isoNowMinus(closedH,  20 + (idx % 30));
  props.mergedAt  = isoNowMinus(mergedH,  25 + (idx % 25));
  return payload;
}

function applyRelativeDeploymentDates(payload, idx) {
  const createdH = Math.max(1, 47 - ((idx % 16) * 3) - Math.floor(idx / 16));
  const props = payload.properties ?? (payload.properties = {});
  props.createdAt = isoNowMinus(createdH, 12 + (idx % 45));
  return payload;
}

function loadPayloads(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .sort()
    .map((f) => path.join(dir, f));
}

async function main() {
  let clientId = process.env.PORT_CLIENT_ID || "";
  let clientSecret = process.env.PORT_CLIENT_SECRET || "";
  const baseUrl = (process.env.PORT_API_BASE_URL || "https://api.port.io").replace(/\/$/, "");

  if (!clientId) clientId = await prompt("Enter PORT_CLIENT_ID: ");
  if (!clientSecret) clientSecret = await promptSecret("Enter PORT_CLIENT_SECRET: ");

  if (!clientId || !clientSecret) {
    console.error("Missing credentials: provide PORT_CLIENT_ID and PORT_CLIENT_SECRET.");
    process.exit(1);
  }

  let authData;
  try {
    ({ data: authData } = await httpJson("POST", `${baseUrl}/v1/auth/access_token`, {
      clientId,
      clientSecret,
    }));
  } catch (e) {
    console.error(`Auth failed: ${e.message}`);
    process.exit(1);
  }

  const token = authData?.accessToken;
  if (!token) {
    console.error("Auth response missing accessToken.");
    process.exit(1);
  }

  const authHeader = { Authorization: `Bearer ${token}` };

  const cleanupOrder = ["deployment", "incident", "pullRequest", "service", "repository"];
  const createOrder  = ["repository", "service", "pullRequest", "deployment", "incident"];

  // Index blueprint files by identifier
  const blueprintFilesById = {};
  if (fs.existsSync(blueprintsRoot)) {
    for (const f of fs.readdirSync(blueprintsRoot).filter((f) => f.endsWith(".json")).sort()) {
      try {
        const payload = JSON.parse(fs.readFileSync(path.join(blueprintsRoot, f), "utf8"));
        if (payload.identifier) blueprintFilesById[payload.identifier] = path.join(blueprintsRoot, f);
      } catch {}
    }
  }

  console.log("== Checking for pre-existing blueprints ==");
  for (const blueprint of cleanupOrder) {
    const { status: checkStatus, err: checkErr } = await maybeRequest("GET", `${baseUrl}/v1/blueprints/${blueprint}`, undefined, authHeader);
    if (checkErr || checkStatus === 404) {
      console.log(`[SKIP] ${blueprint} blueprint does not exist.`);
      continue;
    }
    if (checkStatus !== 200) {
      console.error(`[FAIL] Unable to check blueprint ${blueprint} (HTTP ${checkStatus}).`);
      process.exit(1);
    }

    console.log(`[INFO] Existing blueprint found: ${blueprint}. Deleting entities and blueprint.`);
    const { status: delEntStatus, data: delEntData, err: delEntErr } = await maybeRequest(
      "DELETE", `${baseUrl}/v1/blueprints/${blueprint}/all-entities`, undefined, authHeader
    );
    if (delEntErr && ![200, 404].includes(delEntStatus)) {
      console.error(`[FAIL] Could not delete all entities for ${blueprint} (HTTP ${delEntStatus}) | ${delEntData}`);
      process.exit(1);
    }
    if ([200, 404].includes(delEntStatus)) {
      console.log(`[OK]   Cleared entities for ${blueprint} (HTTP ${delEntStatus}).`);
    }

    await sleep(1000);

    const { status: delBpStatus, data: delBpData, err: delBpErr } = await maybeRequest(
      "DELETE", `${baseUrl}/v1/blueprints/${blueprint}`, undefined, authHeader
    );
    if (delBpErr && ![200, 404].includes(delBpStatus)) {
      console.error(`[FAIL] Could not delete blueprint ${blueprint} (HTTP ${delBpStatus}) | ${delBpData}`);
      process.exit(1);
    }
    console.log(`[OK]   Deleted blueprint ${blueprint} (HTTP ${delBpStatus}).`);
  }

  console.log("\n== Recreating blueprints from local files ==");
  for (const blueprint of createOrder) {
    const bpPath = blueprintFilesById[blueprint];
    if (!bpPath) {
      console.error(`[FAIL] Missing local blueprint file for identifier '${blueprint}'.`);
      process.exit(1);
    }
    const payload = JSON.parse(fs.readFileSync(bpPath, "utf8"));
    const { status, data, err } = await maybeRequest("POST", `${baseUrl}/v1/blueprints`, payload, authHeader);
    if (err || ![200, 201].includes(status)) {
      console.error(`[FAIL] Could not create blueprint ${blueprint} (HTTP ${status}) | ${JSON.stringify(data)}`);
      process.exit(1);
    }
    console.log(`[OK]   Created blueprint ${blueprint}.`);
  }

  console.log("\n== Upserting self-service actions from local files ==");
  for (const f of loadPayloads(actionsRoot)) {
    const payload = JSON.parse(fs.readFileSync(f, "utf8"));
    const actionId = payload.identifier;
    if (!actionId) {
      console.error(`[FAIL] Action file ${path.basename(f)} is missing 'identifier'.`);
      process.exit(1);
    }

    let { status, data, err } = await maybeRequest("PUT", `${baseUrl}/v1/actions/${actionId}`, payload, authHeader);
    if (status === 404) {
      ({ status, data, err } = await maybeRequest("POST", `${baseUrl}/v1/actions`, payload, authHeader));
    }
    if (err || ![200, 201].includes(status)) {
      console.error(`[FAIL] Could not upsert action ${actionId} (HTTP ${status}) | ${JSON.stringify(data)}`);
      process.exit(1);
    }
    console.log(`[OK]   Upserted action ${actionId}.`);
  }

  const importPlan = [
    ["repository",  path.join(entitiesRoot, "repositories")],
    ["service",     path.join(entitiesRoot, "services")],
    ["pullRequest", path.join(entitiesRoot, "pull-requests")],
    ["deployment",  path.join(entitiesRoot, "deployments")],
  ];

  let failures = 0;
  for (const [blueprint, folder] of importPlan) {
    const files = loadPayloads(folder);
    console.log(`\n== Importing ${blueprint} entities from ${path.basename(folder)} (${files.length}) ==`);
    for (let idx = 0; idx < files.length; idx++) {
      const f = files[idx];
      let payload = JSON.parse(fs.readFileSync(f, "utf8"));
      if (blueprint === "pullRequest") payload = applyRelativePrDates(payload, idx);
      else if (blueprint === "deployment") payload = applyRelativeDeploymentDates(payload, idx);

      const { status, data, err } = await maybeRequest(
        "POST", `${baseUrl}/v1/blueprints/${blueprint}/entities`, payload, authHeader
      );
      if (err || ![200, 201].includes(status)) {
        failures++;
        console.log(`[FAIL] ${path.basename(f)} -> HTTP ${status} | ${typeof data === "string" ? data : JSON.stringify(data)}`);
      } else {
        console.log(`[OK]   ${path.basename(f)}`);
      }
    }
  }

  console.log("\nImport complete.");
  if (failures) {
    console.error(`Completed with ${failures} failure(s).`);
    process.exit(1);
  }
  console.log("All entities imported successfully.");
}

main().catch((e) => { console.error(e); process.exit(1); });
