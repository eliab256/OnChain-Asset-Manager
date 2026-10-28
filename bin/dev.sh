#!/usr/bin/env bash
# make dev: Postgres + local chain + contracts + funded accounts, then waits until Ctrl-C.
# DEV_PROFILE=anvil (default): loads $STATE_DIR/31337.json if present, else deploys from scratch.
# DEV_PROFILE=fork: mainnet fork at FORK_BLOCK with chain id 31338, always deployed from scratch.
set -euo pipefail
cd "$(dirname "$0")/.."
source bin/anvil-common.sh

DEV_PROFILE="${DEV_PROFILE:-anvil}"
FORK_BLOCK="${FORK_BLOCK:-26178000}"
FORK_CHAIN_ID="${FORK_CHAIN_ID:-31338}"
POSTGRES_PORT="${POSTGRES_PORT:-5434}"
[ -f .env ] && { set -a; source .env; set +a; }

require_tools docker anvil forge cast jq
require_port_free

docker compose up -d --wait

trap stop_anvil EXIT
# Ctrl-C is the normal way out: stop anvil and exit cleanly
trap 'stop_anvil; exit 0' INT TERM

case "$DEV_PROFILE" in
  anvil)
    CHAIN_ID=31337
    STATE_FILE="$STATE_DIR/31337.json"
    if [ -f "$STATE_FILE" ]; then
      start_anvil --load-state "$STATE_FILE"
      wait_rpc
      INDEX_MANAGER=$(jq -r .indexManager deployments/31337.json)
      if [ "$(cast code "$INDEX_MANAGER" --rpc-url "$RPC_URL")" = "0x" ]; then
        echo "deployments/31337.json does not match $STATE_FILE: run make snapshot again." >&2
        exit 1
      fi
      make refresh-feeds
    else
      start_anvil
      wait_rpc
      make deploy-anvil
    fi
    ;;
  fork)
    CHAIN_ID="$FORK_CHAIN_ID"
    : "${MAINNET_RPC_URL:?MAINNET_RPC_URL is not set in .env}"
    start_anvil --fork-url "$MAINNET_RPC_URL" --fork-block-number "$FORK_BLOCK" --chain-id "$FORK_CHAIN_ID"
    wait_rpc
    make deploy-fork
    ;;
  *)
    echo "Unknown DEV_PROFILE: $DEV_PROFILE (anvil or fork)" >&2
    exit 1
    ;;
esac

cat <<INFO

Dev environment up ($DEV_PROFILE)
  RPC:          $RPC_URL (chain id $CHAIN_ID)
  Contracts:    deployments/$CHAIN_ID.json
  Accounts:     anvil accounts 0-9 with WETH, WBTC and USDC
  Postgres:     postgresql://oam:oam@localhost:$POSTGRES_PORT/oam (make db-down to stop it)
  anvil log:    $ANVIL_LOG

Ctrl-C stops anvil.
INFO

wait "$ANVIL_PID"
