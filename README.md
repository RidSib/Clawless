# Clawless

**Repeatable [OpenClaw](https://github.com/openclaw/openclaw) deployment in under 5 minutes.** Clawless is an open source project that provides safe, repeatable ways to deploy OpenClaw in the cloud — without hardcoding secrets in public configs and with clear separation between code and credentials.

Do the **initial setup once** (Terraform + `cloud-init.yaml`); after that, **no additional setup is required**. Run `terraform apply` and your VM comes up with OpenClaw built and running. No manual install steps, no post-boot configuration. As many instances as you want.

This repo is set up for **Google Cloud** (Terraform + cloud-init provision a single Compute Engine VM that builds and runs OpenClaw in Docker, with Node, Python, and Playwright-friendly tooling). The same pattern — Terraform for the VM plus cloud-init for bootstrap — can be easily adjusted for other cloud providers (AWS, Azure, etc.) by swapping the Terraform provider and instance types; the `cloud-init.yaml` and OpenClaw setup remain largely the same.

## Deploy

1. **Prerequisites:** [Terraform](https://www.terraform.io/downloads) ≥ 1.5, [gcloud](https://cloud.google.com/sdk/docs/install) configured, SSH key at `~/.ssh/id_ed25519.pub` (or set `public_key_path` in tfvars).

2. **Configure:** Copy the example files, then follow the [Tutorial: Setting up cloud-init.yaml](#tutorial-setting-up-cloud-inityaml) below. Also set your GCP project:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   cp cloud-init.yaml.example cloud-init.yaml
   ```
   - Edit `terraform.tfvars`: set `project_id = "your-gcp-project-id"`.
   - Edit `cloud-init.yaml`: replace every `your-*` placeholder (see tutorial). **Never commit `cloud-init.yaml`** — it stays local and gitignored.

3. **Apply:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```
   First boot can take 15–20 minutes while the OpenClaw image builds. Subsequent runs are much faster.

4. **SSH:** Use the `ssh_command` output, e.g. `ssh dev@<nat_ip>`.

## Tutorial: Setting up cloud-init.yaml

After copying `cloud-init.yaml.example` to `cloud-init.yaml`, open `cloud-init.yaml` and replace the following placeholders. Use your editor’s search (e.g. search for `your-`) to find each one.

### Required (default model is OpenAI)

| Placeholder | Variable | Where to get it |
|-------------|----------|------------------|
| `your-openai-api-key` | `OPENAI_API_KEY` | [OpenAI API keys](https://platform.openai.com/api-keys). Used as the primary LLM (default: `openai/gpt-5.2`). |

Replace **every** occurrence of `your-openai-api-key` in the file (there are two: one in the `echo` block, one in the `ENVEOF` block).

### Optional: other model (Gemini)

| Placeholder | Variable | Where to get it |
|-------------|----------|------------------|
| `your-google-api-key` | `GEMINI_API_KEY` | [Google AI Studio](https://aistudio.google.com/apikey). Only needed if you change the default model to Gemini or use Gemini in skills. |

If you don’t use Gemini, you can leave the placeholder or set a dummy value; the default config uses OpenAI only.

### Optional: plugins and integrations

| Placeholder | Variable | Where to get it |
|-------------|----------|------------------|
| `your-telegram-bot-token` | `TELEGRAM_BOT_TOKEN` | [@BotFather](https://t.me/BotFather) on Telegram. Required only if you use the Telegram plugin. |
| `your-telegram-user-id` | (in `openclaw.json`) | Your Telegram user ID (e.g. from [@userinfobot](https://t.me/userinfobot)). Used in `channels.telegram.allowFrom` so the bot accepts your DMs. |
| `your-notion-api-key` | `NOTION_API_KEY` | [Notion integrations](https://www.notion.so/my-integrations). For the Notion skill. |
| `your-vercel-token` | `VERCEL_TOKEN` | [Vercel account tokens](https://vercel.com/account/tokens). For Vercel-related tools. |
| `your-vapi-api-key` | `VAPI_API_KEY` | [VAPI dashboard](https://dashboard.vapi.ai). For voice/API integrations. |
| `your-github-pat` | `GITHUB_TOKEN` | [GitHub Personal Access Token](https://github.com/settings/tokens). For repo access from OpenClaw. |
| `your-apify-token` | `APIFY_TOKEN` | [Apify console](https://console.apify.com/account/integrations). For Apify actors. |

Replace each placeholder only if you use that integration. For unused ones you can leave the placeholder or a dummy value.

### Checklist

1. Copy: `cp cloud-init.yaml.example cloud-init.yaml`
2. Set **at least** `your-openai-api-key` everywhere it appears.
3. Set `your-telegram-user-id` in the `openclaw.json` block if you use Telegram (search for `"allowFrom": ["your-telegram-user-id"]` and put your numeric user ID in the list).
4. Set any other `your-*` values you need for plugins/skills.
5. Save. Do **not** commit `cloud-init.yaml`.

## OpenClaw on the VM

- **Onboarding:** Skipped automatically — `cloud-init.yaml` pre-seeds a full onboarded config from your `.env` values. No wizard to run after boot.
- **Config/workspace:** `~/.openclaw` and `~/.openclaw/workspace` on the VM; gateway runs as a container from `/opt/openclaw`.

### Accessing the Control UI

The Control UI requires HTTPS or localhost (secure context), so you **must** use an SSH tunnel:

```bash
gcloud compute ssh dev@cloud-automation-dev --zone=europe-west3-a -- -N -L 18789:localhost:18789
```

Keep that running, then open **http://localhost:18789** in your browser.

### First-time device pairing

On a fresh deployment, the Control UI will show `disconnected (1008): pairing required`. This is because no browser devices have been approved yet.

1. Get a dashboard link with auto-auth:
   ```bash
   gcloud compute ssh dev@cloud-automation-dev --zone=europe-west3-a \
     --command="cd /opt/openclaw && docker compose run --rm openclaw-cli dashboard --no-open"
   ```
   Open the printed `http://localhost:18789/#token=...` URL.

2. If that still fails (CLI itself needs pairing — chicken-and-egg), approve pending devices manually:
   ```bash
   gcloud compute ssh dev@cloud-automation-dev --zone=europe-west3-a --command="python3 -c \"
   import json, secrets
   pending = json.load(open('/home/dev/.openclaw/devices/pending.json'))
   paired = {}
   for rid, req in pending.items():
       paired[req['deviceId']] = {
           'deviceId': req['deviceId'], 'publicKey': req['publicKey'],
           'platform': req['platform'], 'clientId': req['clientId'],
           'role': req['role'], 'roles': req['roles'], 'scopes': req['scopes'],
           'token': secrets.token_hex(32), 'pairedAt': req['ts']
       }
   with open('/home/dev/.openclaw/devices/paired.json', 'w') as f:
       json.dump(paired, f, indent=2)
   with open('/home/dev/.openclaw/devices/pending.json', 'w') as f:
       json.dump({}, f)
   print('Approved', len(paired), 'devices')
   \""
   ```
   Then restart the gateway:
   ```bash
   gcloud compute ssh dev@cloud-automation-dev --zone=europe-west3-a \
     --command="cd /opt/openclaw && docker compose restart openclaw-gateway"
   ```
   Refresh `http://localhost:18789` — it should connect.

### Token + pairing requirements (important)

- The Control UI auth token is tied to the current deployment and device pairing state.
- After `terraform destroy`/`apply` (or manual device file reset), old browser tokens become invalid.
- Access must be through `localhost` (SSH tunnel) or HTTPS; direct public HTTP is not a secure context.
- Keep one active browser session during first connect to avoid stale token/device collisions.

#### Common errors and fixes

- **`disconnected (1008): pairing required`**
  - No device is paired yet. Use the "First-time device pairing" steps above.
- **`disconnected (1008): unauthorized: device token mismatch (rotate/reissue device token)`**
  1. Generate a fresh dashboard token URL:
     ```bash
     gcloud compute ssh dev@cloud-automation-dev --zone=europe-west3-a \
       --command="cd /opt/openclaw && docker compose run --rm openclaw-cli dashboard --no-open"
     ```
  2. Open the printed `http://localhost:18789/#token=...` URL in your tunneled browser session.
  3. If it still fails, clear site data for `localhost:18789` or use an Incognito window, then retry the token URL.
  4. If needed, run the manual approval snippet from "First-time device pairing", then restart:
     ```bash
     gcloud compute ssh dev@cloud-automation-dev --zone=europe-west3-a \
       --command="cd /opt/openclaw && docker compose restart openclaw-gateway"
     ```

### API prerequisites

- **OpenAI:** The default model is `openai/gpt-5.2`; set `OPENAI_API_KEY` in `cloud-init.yaml` (required).
- **Google/Gemini (optional):** Only needed if you switch the model to Gemini or use it as a fallback. Enable the [Generative Language API](https://console.developers.google.com/apis/api/generativelanguage.googleapis.com/overview) in your GCP project and set `GEMINI_API_KEY`.

## Repo contents

- **Terraform:** `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` — one Ubuntu 22.04 VM in `europe-west3`; firewall allows TCP 18789 for OpenClaw.
- **cloud-init.yaml.example** — template for cloud-init: Docker, Docker Compose, Node 20, Python 3, dev tools; clones OpenClaw, builds the image, and starts the gateway. Copy to `cloud-init.yaml` (gitignored) and fill in your keys.

`.terraform/` and `*.tfstate` are gitignored; run `terraform init` after clone.

## Disclaimer

**We do not take any responsibility for actions taken by or resulting from your use of this deployment.** Infrastructure, cloud resources, and API usage are under your control and at your risk. Use Clawless only if you have the necessary expertise (Terraform, GCP, Docker, networking, and secret management) and exercise appropriate care.

## License and contributing

Clawless is **open source** under the [MIT License](LICENSE). Safe deployment patterns for OpenClaw (like example configs and Terraform) belong in this repo; secrets and keys stay in your local `cloud-init.yaml` and `terraform.tfvars` only.

## TODO

- **Move secrets to Terraform variables:** Define API keys as Terraform variables in `variables.tf`, set values in `terraform.tfvars` (already gitignored), and inject via `templatefile()` — same pattern as `ssh_public_key`. That would make `cloud-init.yaml` a secret-free template safe to commit.
