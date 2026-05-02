# OpenClaw on Azure AI (Foundry) — verified setup

Use this doc when regressions appear after upgrading OpenClaw or changing
Azure routing.

## OpenClaw version reference (working baseline)

The configuration below was exercised end-to-end (real prompts via agent and
infer) against:

- **OpenClaw** `2026.5.2` (printed by `openclaw-cli` banner inside the gateway
  container during validation, **May 2026**).

Deployments in this repo still use **`git clone --depth 1`** of upstream
OpenClaw, so newer builds rotate in automatically; if behaviour changes, compare
against this version using the upstream tag or `--branch`/`ref` pinned in
`cloud-init` if you decide to freeze.

## What was broken and why

Several symptoms looked similar but had different roots:

### 1. Control UI — `origin not allowed`

Browsers enforce an **origin allowlist** for websocket traffic to the gateway.
Either use an SSH tunnel and **`http://localhost:18789`**, or set
`gateway.controlUi.allowedOrigins` so it includes **exactly** your page origin,
for example **`http://<vm-public-ip>:18789`** (replace the placeholder after
deployment).

### 2. Agent chat — Responses API rejects the payload Azure receives

OpenClaw’s **agent** path often uses the **Responses** request shape (`input`
as structured items). For **Azure**, some **user/developer turns arrive without a
`type` field**. Public OpenAI is lenient; **Azure’s Responses validator returns
errors** along the lines of invalid `type` (`''` vs known item types).

**One-shot** `infer model run` can still succeed under that mismatch while the
full agent loop fails → easy to mistake for “Azure is broken”.

### 3. Choosing the adapter and URL together

Incorrect pairings observed in the field:

- **`services.ai.azure.com/.../openai/v1`** + **`azure-openai-responses`** /
  **`api-version` query**: Azure rejects **`api-version`** on **`/openai/v1`**
  paths (“api-version query parameter is not allowed when using /v1 path”).
- **Classic resource host** **`*.cognitiveservices.azure.com`** + wrong path
  + **api-version**: can return **`API version not supported`** depending on the
  exact route.

## Working combination (gpt-5.5 on Foundry project, agent + tools)

**Endpoint (env + provider `baseUrl`):**

`https://<resource>.services.ai.azure.com/api/projects/<project>/openai/v1`

(No trailing slash required; must be this **project OpenAI-compatible** base.)

**Provider block (conceptual):**

- **`api`: `openai-completions`** so the gateway uses **`/chat/completions`**
  (classic `messages` JSON), which **Azure validates consistently** with
  OpenClaw’s agent tooling.
- **`authHeader`: false**, **`headers`**: `{ "api-key": "<Azure key>" }` (same
  pattern this repo uses elsewhere).
- **Model catalogue entry**: **`reasoning`: false** for **`gpt-5.5`** here so OpenClaw
  does **not** send **reasoning-effort** knobs that **Azure rejects alongside
  function/tool calls** on **`/v1/chat/completions`** for this model (“use
  `/v1/responses` instead” when that forbidden combination appears).

Tools remain available; the constraint is specifically **reasoning-effort plus
tools on chat-completions**, not tools in isolation.

Provider **id stays** **`azure-openai-responses`** in `openclaw.json` so the model
binding **`azure-openai-responses/gpt-5.5`** does not need renaming; only the
**`api`** field selects the HTTP adapter.

The canonical YAML for this repo lives in **`cloud-init.yaml.example`** /
**`cloud-init.yaml`** (ignored from git).

## Quick smoke tests on the VM (after bootstrap)

Substitute endpoints and compose location as appropriate:

```bash
cd /opt/openclaw
docker compose exec openclaw-gateway printenv OPENCLAW_GATEWAY_TOKEN
docker compose run --rm openclaw-cli infer model run --gateway \
  --model azure-openai-responses/gpt-5.5 \
  --prompt "Reply with one short sentence: what is 2+2?"
docker compose run --rm openclaw-cli agent \
  --session-id smoke-$(date +%s) \
  --message "Reply with one short sentence: capital of France?" \
  --json --timeout 120
```

If **infer** passes but **agent** fails, re-read section 2 (Responses vs
completions) and confirm **`api` is `openai-completions`**.
