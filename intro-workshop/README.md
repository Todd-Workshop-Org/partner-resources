# Introduction to Port — Self-Guided Workshop

A self-paced, hands-on introduction to building an Internal Developer Portal in Port. By the end, you'll have a working data model, two self-service actions, and a dashboard — the foundation of an Agentic Engineering Platform.

This is the self-guided version of Port's internal intro workshop, adapted for partners working through it on their own schedule — no live session required.

---

## How to Use This Guide

- Work through **Phase 1 → 2 → 3** in order — each phase builds on entities and blueprints created in the one before it.
- Each phase has a **Task** (the one-line goal), **Instructions** (how to get there), a **Checkpoint** (run right away to confirm that phase before moving on), and an **Advanced Option** (skip it on a first pass — come back if you have time).
- Reference material throughout:
  - [Port documentation](https://docs.port.io/)
  - [Port's public demo site](https://demo.port.io/) — browse it for inspiration before building your own version of the same idea, don't copy it verbatim
- This is self-paced — there's no clock running. Take the time each phase actually needs rather than a fixed slot; Phase 2 in particular tends to take longer than it looks the first time you build a dynamic payload.

## Prerequisites

- [ ] A Port account (workshop credentials will have been shared with you separately) — Settings → API to find/generate a **Client ID** and **Client Secret**
- [ ] `curl` and [`jq`](https://jqlang.org/download/) installed locally (used by the completion script; `curl` also useful for exploring the API directly if you want to)
- [ ] A modern browser, logged into your Port account

Export your credentials once, in the terminal you'll use for the completion script later:

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

## Phase 1: Blueprints and Relationships

**Task:** Create at least three blueprints with relationships between them, then populate them with sample data.

### Instructions

1. **Explore first.** Look at the data model that already exists by default in your account. Open a couple of existing blueprints and note the different *property types* available, and how *relationships* are defined between blueprints.

2. **Create 3 new blueprints, in this order:**
   1. `Pull Request`
   2. `Repository`
   3. `Jira Ticket`

   Creating them in this order matters if you want to wire up relationships as you go — a blueprint can only relate to a blueprint that already exists.

3. **Give each blueprint at least 3 properties.** Try a mix of property types (not just strings) — a status enum, a number, a URL, a date, a boolean.

4. **Establish at least 3 relationships between the blueprints.** For example: `Pull Request → Repository`, `Pull Request → Jira Ticket`.
   - Prefer one-to-one relationships defined from the perspective of the **downstream/smallest** blueprint, and avoid many-to-many where you can — it keeps the catalog easier to reason about later.

5. **Create at least 3 sample entities per blueprint**, with relationships between them actually set (not left blank). Try creating a couple by hand first so you understand the form, then try Port's **AI assistant** to generate the rest — it's faster once you know what "realistic" should look like for your blueprints.

6. **Create a team**, and add yourself to it as a member.

### ✅ Checkpoint

```bash
export PORT_USER_EMAIL="you@example.com"   # optional — also checks your team membership
./check-completion.sh --phase 1
```

Fix anything it flags before moving on — Phase 2's actions will target the entities you just created, so it's easier to catch a missing relationship now than after building on top of it.

### Advanced Option

Add a **calculation** or **aggregation** property — a field that's computed from, or summed/counted across, a relationship (e.g., "number of open Pull Requests" rolled up onto `Repository`). Aggregations are what let you build a panoramic view across entities instead of only ever looking at one at a time.

---

## Phase 2: Self-Service Actions

**Task:** Create at least two self-service actions — one that creates a new entity (a "Day 1" operation) and one that modifies an existing entity (a "Day 2" operation).

To keep this workshop simple, build both actions on the **"Create/Update Entity" backend** (a real deployment would usually wire the backend to a CI/CD pipeline — GitHub Actions, Jenkins, Azure DevOps — instead, but that's a separate concern from designing the action itself).

📖 [Self-service actions documentation](https://docs.port.io/actions-and-automations/create-self-service-experiences/)

### Instructions

1. Browse the [Port demo site](https://demo.port.io/) for a few examples, paying attention to how each action's **Backend** section builds its payload from the form inputs.

2. **Build both actions by hand.** Use the AI assistant only to help debug if you get stuck — the point of this phase is understanding the form → payload → backend flow yourself.

3. **Day 1 action — creates a new entity.** For example: create a new Repository, open a Jira ticket, register a new service.
   - At least 2 form inputs, using at least 2 different data types
   - A [dynamic payload](https://docs.port.io/actions-and-automations/create-self-service-experiences/setup-the-backend/#define-the-payload) built from those inputs
   - Run it, and confirm the entity it creates looks right

4. **Day 2 action — modifies an existing entity.** For example: update a Jira ticket's status, merge/close/open a pull request.
   - At least 1 form input
   - Updates at least 1 property on an existing entity
   - A dynamic payload built from the input
   - Run it against a real entity, and confirm the update actually landed

### ✅ Checkpoint

```bash
./check-completion.sh --phase 2
```

This only confirms **≥2 actions exist** — it can't inspect what each one does. Before moving on, double check yourself that one genuinely creates and one genuinely updates, and that you've actually run each at least once successfully (see [Troubleshooting](#troubleshooting) if a run fails).

### Advanced Option

Build a short **workflow** that triggers automatically after an event occurs, rather than being triggered by a person filling out a form.

---

## Phase 3: Dashboards and Agents

**Task:** Create at least one custom dashboard, and one AI agent that can help a developer use it.

### Instructions

1. Look at the dashboards already in your account and in the [Port demo site](https://demo.port.io/) for ideas before building your own.

2. **Create a new dashboard** in the Catalog section.

3. **Add a Table widget** showing entities from one of your Phase 1 blueprints.
   - Customize the columns to show properties that actually matter for that view
   - Add a grouping filter (e.g., group by status)
   - Apply at least one filter to the table (status, language, team — whatever fits your data)
   - Example framings: "Open PRs", "My repositories", "Jira tasks"

4. **Add an Actions widget**, wired to the actions you built in Phase 2.

5. **Create an AI agent** with a prompt that helps a developer prioritize their work, find information, or run an action.
   - 📖 [Building an AI agent](https://docs.port.io/ai-interfaces/ai-agents/build-an-ai-agent/#create-a-new-ai-agent)
   - 💡 [Worked example — a task-manager agent](https://docs.port.io/guides/all/setup-task-manager-ai-agent/)
   - Give it specific *tools*, including at least one of your self-service actions

6. **Optional:** add a Markdown widget welcoming developers to the dashboard with a short usage note.

### ✅ Checkpoint

```bash
./check-completion.sh --phase 3
```

This confirms a page with at least one widget exists — it can't see whether it's actually *your* Phase 3 dashboard versus something else, whether the table's filter/grouping make sense, or whether the AI agent exists at all (Port doesn't expose agents over this API). Give the dashboard a once-over yourself, then run the full check below.

### Advanced Option

Keep going with Port's MCP / in-app AI assistant — vibe-build out the rest of the dashboard. Add other widget types, create a Scorecard and a widget to display it, or use the MCP tools to spin up an entirely new dashboard for a use case of your choosing.

---

## Checking Your Work

You've already run the per-phase checkpoints above. Once all three phases are done, run the same script once more with no `--phase` flag for the full picture:

```bash
chmod +x check-completion.sh
./check-completion.sh
```

It calls the Port API directly with your `PORT_CLIENT_ID` / `PORT_CLIENT_SECRET` and checks, programmatically, for the things each phase asked for: blueprint count/properties/relations, entity counts, a team, action count, and a dashboard with at least one widget.

**What it can't check for you:** relationships being *semantically* sensible (vs. just present), action payloads actually working end-to-end, dashboard filters/grouping being configured well, and whether your AI agent exists and is useful — Port doesn't expose AI agents over the same API surface this script uses, so that one's a manual check. The script tells you exactly which of these are outside what it verified, at the end of its output.

Think of a clean run as "you did the mechanical parts," not "you're finished thinking" — the real signal for that is whether you'd be comfortable explaining your blueprint/relationship choices to a colleague.

---

## Troubleshooting

This anticipates the friction points most likely to come up, based on how Port's data model and action system work — it isn't a list of things confirmed to go wrong in practice, so if you hit something not covered here, that's expected; ask for help (see below) rather than assuming you did something wrong.

**Phase 1**

- *`check-completion.sh` says "No blueprint found matching 'Pull Request'" (or Repository/Jira Ticket) even though you created it* — the checkpoint fuzzy-matches on identifier + title (`pull.?request`, `repo`, `jira`). If you named things very differently than suggested, rename the blueprint's identifier or title to include the expected word.
- *Can't add a relation to a blueprint* — you can only relate to a blueprint that already exists. If you want `Pull Request → Repository`, create `Repository` first. This is why the instructions specify an order.
- *Team-membership check fails even though you added yourself* — confirm `PORT_USER_EMAIL` matches the email your Port user is actually logged in with, and that the team edit was saved (not left in a draft state).

**Phase 2**

- *Your dynamic payload isn't picking up form input values* — Port's action payloads use JQ expressions wrapped in `{{ }}`. Reference a form input with `{{ .inputs.<field_name> }}`, the target entity on a Day-2 action with `{{ .entity }}` / `{{ .entity.identifier }}`, and the running user with `{{ .trigger.by.user.email }}`. Use the **Test JQ** button in the action editor to see exactly what each expression evaluates to before running the action for real.
- *A field silently isn't in the payload when you run the action, even though you defined it* — this is documented behavior, not a bug: if a payload key's JQ expression evaluates to `null`, Port omits that key entirely rather than sending it as `null`. Check the expression with Test JQ.
- *Day-2 action creates a new entity instead of updating the existing one* — confirm the backend is genuinely **Create/Update Entity** (see [the docs for this backend type](https://docs.port.io/actions-and-automations/setup-backend/create-update-entity/)) and that the entity identifier field in the payload correctly resolves to an *existing* entity's identifier, not a new one.

**Phase 3**

- *Can't find "the Actions widget"* — Port's UI wording shifts over time; if a label in this guide doesn't match what you see, the underlying widget type is still there — look for whatever currently represents "buttons that run self-service actions."
- *AI agent doesn't seem to be able to run your action* — confirm the action is actually attached to the agent as a tool, and that the agent has permission to run it.

**The completion script itself**

- *"Could not get an access token"* — double check `PORT_CLIENT_ID` / `PORT_CLIENT_SECRET`, and confirm you're using the right region (`PORT_API_BASE_URL` — see [Prerequisites](#prerequisites)).
- *A warning about a response having no expected array* — Port's API response shape may have changed since this script was written. Run with `--verbose` to see the raw response, and treat the underlying feature (not the script) as the source of truth.

---

## Getting Help

This is self-guided, but you're not on your own if you get stuck.

- Reach out to your **Partner team** contact at Port
- Or post in your shared Slack channel with Port

If something in this guide is wrong, unclear, or out of date with Port's current UI, flag that too — it's useful signal for keeping this workshop current.

---

## Where to Go From Here

- Extend the data model with a blueprint of your own choosing
- Wire a real Day 1/Day 2 action to an actual CI/CD backend instead of Create/Update Entity
- Explore [scorecards](https://docs.port.io/promote-scorecards/) for measuring catalog health
- Read about [Port's automations](https://docs.port.io/actions-and-automations/define-automations/) for event-driven (not form-driven) workflows
