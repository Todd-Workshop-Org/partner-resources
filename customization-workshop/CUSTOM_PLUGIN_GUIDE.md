# Custom Widget Plugin Guide

Build a dashboard to visualize the Services and Incidents synced in the earlier steps, using Port's real custom-widget plugin mechanism.

---

## What a Custom Widget Actually Is

A Port custom-widget plugin is **one self-contained HTML file**. Port runs it inside an `<iframe>` on a dashboard or entity page. There is no project scaffold, no framework requirement, no build step unless you choose one — a plain HTML file with inline `<script>` and `<style>` is a complete, valid plugin.

```
Your HTML file
    ↓ uploaded via CLI
Port's Plugins Manager
    ↓ attached to a Custom Widget on a dashboard
Runs in an iframe, talks to the host via postMessage
```

Two pieces of real tooling exist for this, both under the `@port-labs` npm scope:

| Package | Purpose | Requires |
|---|---|---|
| [`@port-labs/port-plugins-cli`](https://www.npmjs.com/package/@port-labs/port-plugins-cli) | Uploads your HTML file to Port | Node.js **≥22** |
| [`@port-labs/plugins-sdk`](https://www.npmjs.com/package/@port-labs/plugins-sdk) | Optional helper library that wraps the postMessage protocol (plain JS or React) | Node.js ≥22 *only if you bundle it in* |

**You don't need either to author the plugin.** The postMessage contract is simple enough to hand-write in vanilla JS, which is what this guide does — that also sidesteps any Node version issue entirely for the authoring step. Node 22+ is only unavoidable for the final upload command.


## Upload with the CLI

### 1 Node Version

The CLI requires **Node.js ≥22**. If your primary Node is older (`node --version`), install 22 alongside it rather than switching your whole environment:

```bash
# using nvm
nvm install 22
nvm use 22
node --version   # confirm v22.x
```

### 2 Install

```bash
npm install -g @port-labs/port-plugins-cli
```

Or skip the install and run it directly:

```bash
npx @port-labs/port-plugins-cli --help
```

### 3 Save Credentials

Do this once so you don't paste credentials into every command:

```bash
cd plugin
port-plugins config --client-id $PORT_CLIENT_ID --client-secret $PORT_CLIENT_SECRET
```

This writes `.port/config` in the current directory. Use `--global` to write `~/.port/config` instead if you want it available from any directory.

### 4 Upload

```bash
port-plugins upload \
  --file dashboard.html \
  --identifier service-dashboard \
  --title "Service Dashboard" \
  --description "Services and incidents from the mock integration" \
  --upsert
```

`--upsert` means: create it if it doesn't exist, replace it if it does — safe to re-run every time you edit `dashboard.html`.

### 5 Verify

```bash
port-plugins list
```

Should show `service-dashboard` in the table. For full metadata:

```bash
port-plugins get service-dashboard
```

---

## 6 Attach It to a Dashboard

**In the Port UI:**

1. Open (or create) a dashboard
2. Add a widget → choose **Custom Widget**
3. In the plugin picker, select **`service-dashboard`** from the Plugins Manager list
4. Save

Reload the dashboard. Your plugin now runs inside a real Port-hosted iframe, gets a real token and `baseUrl` via `PLUGIN_DATA`, and should render live Service and Incident data.

---

## Iterating

Every edit follows the same loop:

```bash
# edit dashboard.html, then:
port-plugins upload --file dashboard.html --identifier service-dashboard --title "Service Dashboard" --upsert
# refresh the dashboard tab in the browser
```

No rebuild step, no deploy pipeline — it's a static file re-upload.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Stuck on "Waiting for Port…" when opened directly in a browser | Expected — there's no host to answer `REQUEST_PORT_TOKEN` outside an iframe. Test on a real dashboard. |
| Stuck on "Waiting for Port…" *inside* the dashboard, times out after 8s | Open browser devtools on the dashboard page (not inside the iframe — right-click the widget → "Inspect" to land in the right frame) and check the console for `[plugin]` logs. No logs at all means the plugin's own script never ran; logs that stop after "requesting token" mean the host never replied. |
| Console shows `This document requires 'TrustedHTML' assignment. The action has been blocked.` | Trusted Types CSP blocking a `.innerHTML` assignment — see the note in [1.3](#13-what-this-does). This guide's shipped version avoids `.innerHTML` entirely for exactly this reason; if you added your own rendering code using template-string HTML, switch it to `createElement`/`textContent`. |
| Blank or black rectangle with no console error at all | Different cause than the above — likely leftover host-theme CSS variables with an unverified format (see the theming note in [1.3](#13-what-this-does)). This guide's shipped version uses hardcoded colors and no `var()` fallbacks for exactly this reason. |
| `fetch` calls fail with 401 | `portToken` wasn't set before `loadDashboard()` ran — check the console log for the `PORT_TOKEN` message to confirm it arrived and had a non-empty `token` field |
| `npm install -g @port-labs/port-plugins-cli` fails with `EBADENGINE` | Node <22. Use `nvm install 22 && nvm use 22`, then retry |
| `port-plugins upload` fails with a conflict error | Identifier already exists and `--upsert` was omitted — add `--upsert`, or use `port-plugins update <identifier> --file dashboard.html` |
| Tables show "No services/incidents found" | Blueprints/entities from the earlier Ocean integration steps haven't synced yet — check the Port catalog directly first |
| Load fails with an error naming the raw response body | The `entities` array assumption was wrong for your Port instance — the error message includes the actual response so you can see the real shape and adjust `fetchEntities()` to match |

---

## Going Further

The SDK helper package (`@port-labs/plugins-sdk`) wraps this same protocol with a React hook (`usePortPluginData`) and helpers for opening the AI chat, running actions/workflows from your plugin, and merging dashboard page filters into your own queries — worth reaching for once the vanilla version above is working and you want richer interaction than static tables. It requires a bundler step (to produce one HTML file) and the same Node ≥22 as the CLI.

## Resources

- [`@port-labs/port-plugins-cli` on npm](https://www.npmjs.com/package/@port-labs/port-plugins-cli)
- [`@port-labs/plugins-sdk` on npm](https://www.npmjs.com/package/@port-labs/plugins-sdk)
- [Custom widgets — Port docs](https://docs.port.io/interface-builder/port-interface/dashboards/custom-widgets/)
