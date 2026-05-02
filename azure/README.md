# Clawless on Azure

Azure variant of Clawless using the same bootstrap model as GCP:
Terraform provisions one Ubuntu VM, and `cloud-init.yaml` bootstraps OpenClaw.

OpenClaw ↔ Azure quirks (validated adapter shape, **`gpt-5.5`**, Control UI origins,
smoke commands, **pinned working OpenClaw version note**):

[`../docs/openclaw-azure.md`](../docs/openclaw-azure.md)

## Prerequisites

- Terraform >= 1.5
- Azure CLI (`az`) installed
- Logged in to Azure:
  - `az login`
  - `az account set --subscription "<your-subscription-id-or-name>"`
- SSH public key exists at `~/.ssh/id_ed25519.pub` (or override
  `public_key_path`)

## Shared cloud-init strategy

This stack intentionally reuses the repository root `cloud-init.yaml` as the
single source of truth.

1. In repo root:
   - `cp cloud-init.yaml.example cloud-init.yaml`
2. Edit `cloud-init.yaml` and replace required `your-*` placeholders.
3. Never commit `cloud-init.yaml` (already gitignored).

## Deploy

From the `azure/` folder:

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

**One-shot apply + tunnel + token URL (from repo root):** see
[`../scripts/clawless-post-deploy.sh`](../scripts/clawless-post-deploy.sh) and
[`../README.md`](../README.md) (section *Post-deploy helper*).

Before `terraform apply`, verify `cloud-init.yaml` has real keys (not
placeholders), especially:

- `AZURE_OPENAI_API_KEY` and **`AZURE_OPENAI_ENDPOINT`** (required — Foundry project OpenAI-compatible base `.../openai/v1`; see **`docs/openclaw-azure.md`**)
- `OPENAI_API_KEY` (optional — used as fallback if Azure OpenAI is unreachable)
- **Telegram:** real **`TELEGRAM_BOT_TOKEN`** in **`cloud-init.yaml`** (both `.env` blocks) **and** numeric **`telegram_user_id`** in **`terraform.tfvars`**. See root [**README**](../README.md).
- Any other integration keys you expect to work on first boot

Use outputs:

- `ssh_command` for shell access.
- `openclaw_control_ui` for the direct UI URL.

The recommended Control UI path is still a localhost tunnel:

```bash
ssh -N -L 18789:localhost:18789 dev@<vm-public-ip>
```

Then open `http://localhost:18789`. Direct public HTTP access requires
`gateway.controlUi.allowedOrigins` to include the exact public origin and still
requires the current gateway token.

## Security posture

- Parity mode currently allows inbound `22` and `18789` from anywhere.
- Recommended hardening: remove the `18789` NSG rule and access UI only via
  SSH tunnel (`ssh -N -L 18789:localhost:18789 ...`), then open
  `http://localhost:18789`.

## Safe switching runbook (GCP <-> Azure)

To avoid duplicate cost and state confusion:

1. Deploy/apply target cloud.
2. Verify OpenClaw boots and tunnel/UI works.
3. Destroy previous cloud stack when cutover is complete.

Keep Terraform state isolated per stack (`/` for GCP, `azure/` for Azure).

## Validation and troubleshooting checklist

- `terraform fmt -recursive` from repo root.
- `terraform validate` from `azure/`.
- First boot may take 15-20 minutes while Docker image builds.
- If bootstrap fails, inspect cloud-init logs on VM:
  - `sudo cloud-init status --long`
  - `sudo journalctl -u cloud-init -u cloud-final --no-pager`
- If you edit `/opt/openclaw/.env` on the VM after deployment, recreate
  containers so new env values are loaded:
  - `cd /opt/openclaw && docker compose down && docker compose up -d openclaw-gateway`
  - `docker compose restart` alone may keep old env values in the running
    container.
