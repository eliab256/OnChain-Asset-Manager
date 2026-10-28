#!/usr/bin/env bash
# make snapshot: fresh anvil, deploy + fund, state dumped to $STATE_DIR/31337.json on exit.
set -euo pipefail
cd "$(dirname "$0")/.."
source bin/anvil-common.sh

require_tools anvil forge cast
require_port_free

STATE_FILE="$STATE_DIR/31337.json"
rm -f "$STATE_FILE"
trap stop_anvil EXIT

start_anvil --dump-state "$STATE_FILE"
wait_rpc
make deploy-anvil
stop_anvil

[ -s "$STATE_FILE" ] || { echo "Snapshot not written: $STATE_FILE" >&2; exit 1; }
echo "Snapshot saved to $STATE_FILE (deployments/31337.json describes it)"
