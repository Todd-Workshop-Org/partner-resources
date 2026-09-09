# Advanced Workshop — AI Agents & Agentic Workflows

A self-paced, hands-on workshop demonstrating Port as an Agentic Engineering Platform (AEP). You'll build two AI agents, then wire them into a real, running agentic workflow that triages and remediates incidents automatically.

This assumes you've already been through the [Intro Workshop](../intro-workshop/) or are otherwise comfortable with Port's core concepts (blueprints, entities, relations, self-service actions). This workshop goes further: AI agents, and Port's newer **Workflows** feature (currently in beta).

---

## How to Use This Guide

- Work through **Setup → Phase 1 → 2 → 3** in order — each phase builds directly on the previous one's output.
- Each phase has a **Task**, **Instructions**, a **Checkpoint** (run right away to confirm before moving on), and an **Advanced Option**.
- This is self-paced — there's no clock running and no live walkthrough. Reference material throughout:
  - [Port documentation](https://docs.port.io/)
  - [Port's public demo site](https://demo.port.io/)

## Prerequisites

- [ ] A Port account (workshop credentials shared with you separately) — Settings → API for a **Client ID** and **Client Secret**
- [ ] **Node.js** ([nodejs.org](https://nodejs.org)) **or** **Python 3** ([python.org/downloads](https://www.python.org/downloads)) — either works, you only need one
- [ ] **Git** ([git-scm.com/downloads](https://git-scm.com/downloads)) — optional; only needed if you clone this repo instead of downloading it as a zip
- [ ] `curl` and [`jq`](https://jqlang.org/download/) — used by the completion script
- [ ] A modern browser, logged into your Port account

```bash
export PORT_CLIENT_ID="your-client-id"
export PORT_CLIENT_SECRET="your-client-secret"
```

If your Port account is on the **US** region rather than the default EU one, also set:

```bash
export PORT_API_BASE_URL="https://api.us.port.io"
```

(Check with whoever gave you the workshop credentials if you're not sure which region you're on.)

---

## Setup: Load the Seed Data

Before Phase 1, load a pre-built data model into your account — services, repositories, deployments, pull requests, an `incident` blueprint, and a self-service action to create incidents. This is the foundation the rest of the workshop builds on.

```bash
node seed/scripts/import-entities.js
# or:
python3 seed/scripts/import-entities.py
```

See [`seed/README.md`](seed/README.md) for exactly what this loads and what it touches. **It's destructive to the blueprints it manages** (`repository`, `service`, `pullRequest`, `deployment`, `incident`) — it deletes and recreates them, so don't point it at an account with data you care about.

### ✅ Checkpoint

```bash
chmod +x check-completion.sh
./check-completion.sh --phase setup
```

Confirms the five blueprints exist with sample entities loaded. Fix anything it flags before continuing — every later phase depends on this data being in place.

---

## Phase 1: AI Agents

**Task:** Create two AI agents, each with a specific prompt and purpose, and test one of them end-to-end.

### Instructions

1. **Explore the loaded data model.** Look at the blueprints, entities, and the `Create Workflow Incident` self-service action that the seed script just created.

2. **Create two agents**, using the prompts in [`seed/agent-prompts/`](seed/agent-prompts/):
   - **Triage Agent** — using [`triage-prompt.md`](seed/agent-prompts/triage-prompt.md)
   - **Remediation Agent** — using [`remediation-prompt.md`](seed/agent-prompts/remediation-prompt.md)
   - Follow [Port's guide to building an AI agent](https://docs.port.io/ai-interfaces/ai-agents/build-an-ai-agent)

3. **Add a few conversation starters** to each agent.

4. **Create a chat widget** for each agent on a new dashboard — see [interacting with AI agents](https://docs.port.io/ai-interfaces/ai-agents/interact-with-ai-agents).

5. **Create a sample incident** using the `Create Workflow Incident` self-service action.

6. **Test the Triage Agent:**
   - From its chat widget, pick a conversation starter
   - Check the output in the widget

### ✅ Checkpoint

```bash
./check-completion.sh --phase 1
```

Confirms at least one incident entity exists (created via the self-service action). It **cannot** confirm your two agents exist, that they're using the right prompts, or that the chat widgets work — Port doesn't expose agents over the API this script uses. Confirm those yourself: run the Triage Agent from its widget and read the actual output before moving on.

### Advanced Option

Create a third agent with a different prompt, and give it a **tool** that lets it run the `Create Workflow Incident` self-service action itself. Port's in-app [AI Assistant](https://docs.port.io/ai-interfaces/port-ai-assistant) can help you build this.

---

## Phase 2: Workflows

**Task:** Create a workflow with at least 3 nodes (1 trigger, 1 action, 1 condition). This is the foundation Phase 3 builds on.

> Port's **Workflows** feature is currently in beta. Each node is configured directly in JSON for now — the assisted builder arrives at GA. Expect the UI here to change faster than the rest of Port's product.

To keep this workshop simple, use the **"Create/Update Entity" backend** for the action node (a real deployment would typically wire this to a CI/CD pipeline instead — GitHub Actions, Jenkins, Azure DevOps — but that's a separate concern from designing the workflow itself).

### Instructions

1. **Create a new workflow:** Builder → Workflows, name it something like *"Agentic Incident Management Workflow"*.

2. On the next screen, click **+** where it asks *"What triggers the workflow?"*, and choose **"An Entity Is Created"** — targeting a new entity of the `incident` blueprint.

3. **Node 1 — Trigger.** Set:
   - `blueprintIdentifier`: `incident`
   - Variables: `event_type`, `incident_identifier`

   You must reference the creation event itself to extract these. Unlike Port's existing automations, workflow trigger nodes currently use JQ of the form `{{ .result.diff.after... }}` to pull data out of the event — use the **Execute Node** button to see a real example payload before writing the expression. Update any other fields as you prefer.

4. **Node 2 — Update Entity.** This updates the incident's `status` and `incident_owner`.
   - Add a new node of type **Create/Update Entity**
   - Set the blueprint to `incident`
   - In the mapping section:
     - Set the entity identifier using the variable from Node 1
     - Set `status` to `"acknowledged"`
     - Set `incident_owner` to `"Port AI"`
   - **Test it:** create a new incident via the self-service action and confirm both properties actually update.

5. **Node 3 — Control Flow.** This shows a basic branch based on whether the incident looks like a known, common problem.
   - Add a **Control Flow** node
   - Set `title`, `options.title`, and `options.expression`
   - For the expression, use the `event_type` variable and write a logic check for whether the event is a `"500 Error"`
   - **Test it:** create a new incident via the self-service action and confirm the node evaluates the event type correctly.

### ✅ Checkpoint

```bash
./check-completion.sh --phase 2
```

Checks for at least one incident entity with `status = "acknowledged"` and `incident_owner = "Port AI"` — concrete proof Nodes 1 and 2 actually ran end-to-end. It **cannot** confirm the control-flow node's branch logic is correct; verify that yourself by creating one incident of each `event_type` and checking the run history.

### Advanced Option

*(Continues directly into Phase 3 below — there's no separate advanced option for Phase 2; the next phase is the advanced version of this one.)*

---

## Phase 3: Agentic Workflow

**Task:** Add at least 4 more nodes (2 AI, 2 actions) to your Phase 2 workflow, using both agents from Phase 1.

### Instructions

1. **Node 4 — Triage Agent.** Branch: the incident is *not* a typical, clearly-automatable case.
   - From the control-flow node, add an **Invoke custom Port AI agent** node
   - Set `Title`, `Description`, `userPrompt` (use [`seed/ai-node-prompts/triage-node.md`](seed/ai-node-prompts/triage-node.md), or your own variant), and `agentIdentifier` (your Triage Agent's identifier)

2. **Node 5 — Update Entity.** Writes the triage plan back onto the incident.
   - Add a **Create/Update Entity** node linked to Node 4
   - Set `Title`, `Description`, `blueprintIdentifier`, `mapping.identifier` (the incident's identifier), `mapping.properties.status` to `"investigating"`, and `mapping.properties.incident_triage` to Node 4's response

3. **Node 6 — Remediation Agent.** Branch: the incident *is* a typical, clearly-automatable case.
   - From the control-flow node, add another **Invoke custom Port AI agent** node
   - Set `Title`, `Description`, `userPrompt` (use [`seed/ai-node-prompts/remediation-node.md`](seed/ai-node-prompts/remediation-node.md), or your own variant), and `agentIdentifier` (your Remediation Agent's identifier)

4. **Node 7 — Update Entity.** Writes the remediation plan back onto the incident.
   - Add a **Create/Update Entity** node linked to Node 6
   - Set `Title`, `Description`, `blueprintIdentifier`, `mapping.identifier`, `mapping.properties.status` to `"remediating"`, and `mapping.properties.remediation_plan` to Node 6's response

5. **Test the whole flow end to end.** Use the self-service action to create one **"Out of Memory"** incident and one **"500 Error"** incident — between the two, you should exercise both branches (triage and remediation).

### ✅ Checkpoint

```bash
./check-completion.sh --phase 3
```

Checks that at least one incident has `incident_triage` populated and at least one has `remediation_plan` populated — proof both agent branches actually ran and wrote their output back. It **cannot** confirm the agents' output is good, only that something landed. Read the actual triage and remediation text on a couple of incidents before calling this done.

### Advanced Option

If there's time: add chat widgets and other visualizations to an incident entity's own dashboard page, so an on-call engineer can see the whole triage/remediation story without leaving the entity.

---

## Checking Your Work

Run the full script with no `--phase` flag once all three phases are done, for the complete picture:

```bash
./check-completion.sh
```

**What it verifies:** the seed data loaded correctly, at least one incident exists, at least one incident shows evidence of Phase 2's update-entity node having run, and at least one shows evidence of Phase 3's agent nodes having run.

**What it can't check:** whether your two (or three) agents exist and use the intended prompts, whether the chat widgets actually work, whether the control-flow node's branch logic is correct, and whether the AI agents' triage/remediation output is actually *good* — Port doesn't expose agents over the API this script uses, and workflow run history/branch logic isn't something this script inspects either. A clean run means the mechanical, API-visible parts are there — not that you're done reading and judging the agents' output.

---

## Troubleshooting

This anticipates likely friction points based on how Port's workflow and agent features work — it isn't a list of things confirmed to break in practice. If you hit something not covered here, that's expected; ask for help (see below).

**Setup**

- *Import script fails partway through* — it's meant to be re-run; it deletes and recreates the managed blueprints each time, so a partial failure followed by a clean re-run should self-correct.
- *"Enter PORT_CLIENT_ID" prompt appears unexpectedly* — the script only prompts when the corresponding environment variable isn't set. Confirm you actually `export`ed both variables in the *same* terminal session you're running the script from.

**Phase 1**

- *Agent gives a generic or off-topic answer* — double-check you pasted the full prompt file, not a truncated version, and that the conversation starter you picked is actually one that references an incident.
- *`Create Workflow Incident` action doesn't appear* — confirm the seed import actually completed; it upserts this action as part of setup, you don't create it yourself.

**Phase 2**

- *Trigger node's variables come back empty* — the docs' guidance is to extract them from `{{ .result.diff.after... }}` on the creation event; use **Execute Node** to see the real event shape before assuming a field name.
- *Node 2 doesn't seem to update the entity* — confirm the entity identifier mapping actually references the variable produced by Node 1, not a hardcoded value.
- *Checkpoint still fails after Node 2 looks right in the UI* — property values are case- and spelling-sensitive; the checkpoint looks for the literal strings `"acknowledged"` and `"Port AI"`.

**Phase 3**

- *Agent node fails or times out* — confirm `agentIdentifier` matches your actual agent's identifier exactly (not its display title).
- *`incident_triage` or `remediation_plan` stays empty* — confirm the Create/Update Entity node's mapping actually references the AI node's output, and that you tested with an incident that takes that specific branch.

**The completion script itself**

- *"Could not get an access token"* — double-check `PORT_CLIENT_ID` / `PORT_CLIENT_SECRET`, and your region (`PORT_API_BASE_URL`).
- *A warning about a response having no expected array* — Port's API response shape may have changed since this script was written. Run with `--verbose` to see the raw response.

---

## Getting Help

This is self-guided, but you're not on your own if you get stuck.

- Reach out to your **Partner team** contact at Port
- Or post in your shared Slack channel with Port

If something in this guide is wrong, unclear, or out of date with Port's current UI (especially likely for **Workflows**, which is in active beta), flag that too.

---

## Where to Go From Here

- Wire the workflow's action nodes to a real backend (webhook, GitHub Actions, etc.) instead of Create/Update Entity
- Add a third branch to the control flow for a different `event_type`
- Extend the agents with more tools, or give them access to more of your catalog
- Read about [Port's automations](https://docs.port.io/actions-and-automations/define-automations/) — the GA, event-driven counterpart to the beta Workflows feature used here
