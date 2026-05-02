#!/usr/bin/env bash
# Full Azure/GCP rerun: terraform destroy → apply → clawless-post-deploy.sh
# Prints a wall-clock marker before/after each phase (cumulative seconds).
#
# Usage:
#   ./scripts/clawless-full-redeploy.sh
#   ./scripts/clawless-full-redeploy.sh --cloud gcp
#
# Options:
#   --cloud azure|gcp     stack directory (default: azure)
#   --skip-destroy        only apply + post-deploy (same VM name / drift fix)
#   --skip-post-deploy    destroy + apply only (no SSH wait / tunnel / URL file)
#   --no-notify           post-deploy without --notify-telegram
#   --no-strict           post-deploy without --strict-config
#   --no-tunnel           post-deploy without --tunnel

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUD="azure"
DO_DESTROY=true
DO_POST_DEPLOY=true
PD_NOTIFY=(--notify-telegram)
PD_STRICT=(--strict-config)
PD_TUNNEL=(--tunnel)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)
      CLOUD="$2"
      shift 2
      ;;
    --skip-destroy)
      DO_DESTROY=false
      shift
      ;;
    --skip-post-deploy)
      DO_POST_DEPLOY=false
      shift
      ;;
    --no-notify)
      PD_NOTIFY=()
      shift
      ;;
    --no-strict)
      PD_STRICT=()
      shift
      ;;
    --no-tunnel)
      PD_TUNNEL=()
      shift
      ;;
    -h | --help)
      sed -n '1,25p' "$0" | tail -n +2
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 1
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

T0=$(date +%s)
log_marker() {
  echo ""
  echo "======== $(date '+%Y-%m-%d %H:%M:%S %z') $1" \
    "(cumulative: $(($(date +%s) - T0))s) ========"
}

log_marker "START clawless-full-redeploy (cloud=${CLOUD})"

if $DO_DESTROY; then
  log_marker "BEFORE terraform destroy"
  terraform -chdir="$STACK_DIR" destroy -auto-approve
  log_marker "AFTER terraform destroy"
fi

log_marker "BEFORE terraform apply"
terraform -chdir="$STACK_DIR" apply -auto-approve
log_marker "AFTER terraform apply"

if $DO_POST_DEPLOY; then
  POST_ARGS=(--cloud "$CLOUD")
  [[ ${#PD_TUNNEL[@]} -gt 0 ]] && POST_ARGS+=("${PD_TUNNEL[@]}")
  [[ ${#PD_STRICT[@]} -gt 0 ]] && POST_ARGS+=("${PD_STRICT[@]}")
  [[ ${#PD_NOTIFY[@]} -gt 0 ]] && POST_ARGS+=("${PD_NOTIFY[@]}")
  log_marker "BEFORE post-deploy (${POST_ARGS[*]})"
  "$REPO/scripts/clawless-post-deploy.sh" "${POST_ARGS[@]}"
  log_marker "AFTER post-deploy"
fi

log_marker "DONE clawless-full-redeploy"
