#!/usr/bin/env bash
# Clawless: terraform apply (optional), wait for SSH + gateway, smoke checks,
# optional localhost tunnel, print (and save) Control UI URL with gateway token.
#
# Usage:
#   ./scripts/clawless-post-deploy.sh --cloud azure --apply --tunnel
#   ./scripts/clawless-post-deploy.sh --cloud gcp             # verify only
#   ./scripts/clawless-post-deploy.sh --cloud azure --tunnel --open
#   ./scripts/clawless-post-deploy.sh --cloud azure --tunnel --notify-telegram
#
# Flags:
#   --cloud azure|gcp
#   --apply           terraform apply -auto-approve in that stack
#   --tunnel          ssh -f -N -L 127.0.0.1:18789:127.0.0.1:18789 (background)
#   --no-wait-gateway skip waiting for HTTP on VM :18789
#   --open            macOS: open the token URL (requires working tunnel)
#   --strict-config   exit non-zero if Telegram placeholders detected (local + VM)
#   --notify-telegram send a DM via Telegram Bot API (allowFrom[0]) when up
#
# Env:
#   MAX_WAIT_GATEWAY_SEC  max wait for :18789 (default 2400 ≈ 40 min first boot)
#   SSH_WAIT_ATTEMPTS     SSH retry count (default 180 × 5s ≈ 15 min)
#   TELEGRAM_PING_TEXT    message for --notify-telegram (default: I just came online!)
#
# Every major step prints [timestamp] … (phase +Xs, total Ys ~ Zm Ws).

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUD="azure"
DO_APPLY=false
DO_TUNNEL=false
WAIT_GATEWAY=true
OPEN_BROWSER=false
STRICT_CONFIG=false
NOTIFY_TELEGRAM=false
MAX_WAIT_GATEWAY_SEC="${MAX_WAIT_GATEWAY_SEC:-2400}"
SSH_POLL_SEC=5
GATEWAY_POLL_SEC=15
# Max iterations for SSH wait loop (interval SSH_POLL_SEC each). Default 180 ≈ 15 min.
SSH_WAIT_ATTEMPTS="${SSH_WAIT_ATTEMPTS:-180}"

ts_now() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

fmt_dur() {
  local s=$1
  local m=$((s / 60))
  local r=$((s % 60))
  printf '%dm %02ds' "$m" "$r"
}

# RUN_START / PHASE_START set after stack dir is known (see below).
log_phase() {
  local wall
  wall=$(ts_now)
  local total=$((SECONDS - RUN_START))
  local phase=$((SECONDS - PHASE_START))
  printf '[%s] %s (phase +%ds, total %ds ~ %s)\n' \
    "$wall" "$1" "$phase" "$total" "$(fmt_dur "$total")"
  PHASE_START=$SECONDS
}

usage() {
  sed -n '1,48p' "$0" | tail -n +2
  exit "${1:-0}"
}

preflight_telegram_local() {
  local bad=false
  local cf="$REPO/cloud-init.yaml"
  if [[ -f "$cf" ]] && grep -qF 'your-telegram-bot-token' "$cf" 2>/dev/null; then
    echo "WARNING: $cf still contains your-telegram-bot-token — Telegram cannot work until you set a real BotFather token." >&2
    bad=true
  fi
  local tfvars="$STACK_DIR/terraform.tfvars"
  if [[ -f "$tfvars" ]] && grep -qE 'telegram_user_id\s*=\s*"your-telegram-user-id"' "$tfvars" 2>/dev/null; then
    echo "WARNING: $tfvars still has telegram_user_id placeholder — allowlists will be invalid." >&2
    bad=true
  fi
  if $bad && $STRICT_CONFIG; then
    echo "Strict mode: fix Telegram placeholders (see README) and retry." >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)
      CLOUD="$2"
      shift 2
      ;;
    --apply)
      DO_APPLY=true
      shift
      ;;
    --tunnel)
      DO_TUNNEL=true
      shift
      ;;
    --no-wait-gateway)
      WAIT_GATEWAY=false
      shift
      ;;
    --open)
      OPEN_BROWSER=true
      shift
      ;;
    --strict-config)
      STRICT_CONFIG=true
      shift
      ;;
    --notify-telegram)
      NOTIFY_TELEGRAM=true
      shift
      ;;
    -h | --help)
      usage 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
  esac
done

case "$CLOUD" in
  azure) STACK_DIR="$REPO/azure" ;;
  gcp) STACK_DIR="$REPO" ;;
  *)
    echo "--cloud must be azure or gcp" >&2
    exit 1
    ;;
esac

if [[ ! -d "$STACK_DIR/.terraform" ]]; then
  echo "Run: terraform -chdir=$STACK_DIR init" >&2
  exit 1
fi

RUN_START=$SECONDS
PHASE_START=$SECONDS
printf '[%s] clawless-post-deploy start (cloud=%s apply=%s tunnel=%s notify_tg=%s)\n' \
  "$(ts_now)" "$CLOUD" "$DO_APPLY" "$DO_TUNNEL" "$NOTIFY_TELEGRAM"

preflight_telegram_local
log_phase "Preflight (local Telegram) OK"

if $DO_APPLY; then
  echo "==> terraform apply ($CLOUD)"
  terraform -chdir="$STACK_DIR" apply -auto-approve
fi
log_phase "Terraform apply (or skipped)"

echo "==> Reading SSH from terraform output"
SSH_CMD="$(terraform -chdir="$STACK_DIR" output -raw ssh_command)"
SSH_USER="$(echo "$SSH_CMD" | sed -E 's/^ssh ([^@]+)@(.+)$/\1/')"
SSH_HOST="$(echo "$SSH_CMD" | sed -E 's/^ssh ([^@]+)@(.+)$/\2/')"

if [[ -z "$SSH_HOST" || -z "$SSH_USER" ]]; then
  echo "Could not parse ssh_command: $SSH_CMD" >&2
  exit 1
fi

# Replacing the VM reuses the same public IP on Azure: drop stale host key or
# SSH fails with REMOTE HOST IDENTIFICATION HAS CHANGED.
ssh-keygen -R "$SSH_HOST" 2>/dev/null || true

echo "==> Waiting for SSH ($SSH_USER@$SSH_HOST) ..."
ssh_ok=false
for _ in $(seq 1 "$SSH_WAIT_ATTEMPTS"); do
  if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    "$SSH_USER@$SSH_HOST" true 2>/dev/null; then
    ssh_ok=true
    break
  fi
  sleep "$SSH_POLL_SEC"
done
if ! $ssh_ok; then
  echo "SSH never became available." >&2
  exit 1
fi
log_phase "SSH reachable"

run_remote() {
  ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
    "$SSH_USER@$SSH_HOST" "$@"
}

# Sends one DM using Telegram Bot API (not the OpenClaw agent). Uses VM token +
# first channels.telegram.allowFrom id. Fails soft if user never /start'd bot.
notify_telegram_online() {
  local text="${TELEGRAM_PING_TEXT:-I just came online!}"
  local b64
  b64=$(printf '%s' "$text" | base64 | tr -d '\n')
  echo "==> Telegram online ping (Bot API → allowFrom[0])"
  run_remote bash -s "$b64" <<'REMOTE'
set -uo pipefail
TEXT=$(printf '%s' "$(echo "$1" | base64 -d)")
TOK=$(grep '^TELEGRAM_BOT_TOKEN=' /home/dev/.openclaw/.env | cut -d= -f2- | tr -d '\r')
if [[ -z "${TOK}" || "${TOK}" == *your-telegram* ]]; then
  echo "    SKIP: no real TELEGRAM_BOT_TOKEN"
  exit 0
fi
CID=$(python3 -c "import json;d=json.load(open('/home/dev/.openclaw/openclaw.json'));print(d['channels']['telegram']['allowFrom'][0])")
if [[ -z "${CID}" || "${CID}" == *your-telegram* ]]; then
  echo "    SKIP: allowFrom not configured"
  exit 0
fi
if ! curl -sf --connect-timeout 15 --max-time 30 -X POST \
      "https://api.telegram.org/bot${TOK}/sendMessage" \
      --data-urlencode "chat_id=${CID}" \
      --data-urlencode "text=${TEXT}" \
      >/dev/null; then
  echo "    WARNING: sendMessage failed (open @BotFather bot and send /start?)" >&2
  exit 0
fi
echo "    Telegram ping sent."
REMOTE
}

preflight_telegram_remote() {
  local bad=false
  if run_remote 'grep -qF your-telegram-bot-token /opt/openclaw/.env 2>/dev/null'; then
    echo "WARNING: VM /opt/openclaw/.env still has TELEGRAM placeholder." >&2
    bad=true
  fi
  if run_remote 'grep -qF your-telegram-user-id /home/dev/.openclaw/openclaw.json 2>/dev/null'; then
    echo "WARNING: VM openclaw.json still has telegram user id placeholder." >&2
    bad=true
  fi
  if $bad && $STRICT_CONFIG; then
    echo "Strict mode: redeploy with real telegram_user_id + TELEGRAM_BOT_TOKEN, or fix files on VM and restart gateway." >&2
    exit 2
  fi
}

preflight_telegram_remote
log_phase "Preflight (VM Telegram) OK"

if $WAIT_GATEWAY; then
  echo "==> Waiting for gateway HTTP on VM :18789 (max ${MAX_WAIT_GATEWAY_SEC}s) ..."
  w=0
  gw_ok=false
  while [[ "$w" -lt "$MAX_WAIT_GATEWAY_SEC" ]]; do
    if run_remote \
      'curl -sf --connect-timeout 5 --max-time 8 http://127.0.0.1:18789/ >/dev/null' \
      2>/dev/null; then
      gw_ok=true
      break
    fi
    echo "    ... not ready yet (${w}s)"
    sleep "$GATEWAY_POLL_SEC"
    w=$((w + GATEWAY_POLL_SEC))
  done
  if ! $gw_ok; then
    echo "Gateway did not respond in time. Check: cloud-init, docker compose logs" >&2
    exit 1
  fi
  echo "    Gateway responded."
fi
log_phase "Gateway HTTP on VM :18789 (or skipped)"

echo "==> Smoke checks"
run_remote 'sudo cloud-init status 2>/dev/null || true'
run_remote 'cd /opt/openclaw && docker compose ps' || true

echo "==> Gateway token"
TOKEN="$(run_remote 'cat /home/dev/.openclaw-gateway-token' | tr -d '\r\n')"
if [[ -z "$TOKEN" ]]; then
  echo "Token file empty or missing." >&2
  exit 1
fi

log_phase "Smoke checks + gateway token read"

if $NOTIFY_TELEGRAM; then
  notify_telegram_online
  log_phase "Telegram notify (or skipped)"
fi

UI_URL="http://localhost:18789/#token=${TOKEN}"
LAST_FILE="$REPO/.clawless-last-ui.url"
printf '%s\n' "$UI_URL" >"$LAST_FILE"
chmod 600 "$LAST_FILE" 2>/dev/null || true

if $DO_TUNNEL; then
  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:18789 -sTCP:LISTEN 2>/dev/null | grep -q .; then
      echo "WARNING: something already listens on 18789; tunnel may fail." >&2
      echo "    lsof -iTCP:18789 -sTCP:LISTEN" >&2
    fi
  fi
  echo "==> SSH tunnel in background (-f) localhost:18789 -> VM"
  ssh -f -N -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
    -L "127.0.0.1:18789:127.0.0.1:18789" \
    "$SSH_USER@$SSH_HOST"
  sleep 1
  if command -v curl >/dev/null 2>&1; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 \
      http://127.0.0.1:18789/ || true)"
    echo "    Local probe http://127.0.0.1:18789/ -> HTTP $code"
  fi
fi
log_phase "SSH tunnel + local probe (or skipped)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Control UI (after tunnel):"
echo "$UI_URL"
echo ""
echo "Saved: $LAST_FILE"
echo "Manual tunnel (foreground):"
echo "  ssh -N -L 18789:localhost:18789 $SSH_USER@$SSH_HOST"
total_s=$((SECONDS - RUN_START))
echo "  Total wall time: ${total_s}s (~$(fmt_dur "$total_s"))  [finished $(ts_now)]"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if $OPEN_BROWSER; then
  if [[ "$(uname -s)" == Darwin ]] && command -v open >/dev/null 2>&1; then
    open "$UI_URL"
  else
    echo "(--open only implemented for macOS 'open')" >&2
  fi
fi
