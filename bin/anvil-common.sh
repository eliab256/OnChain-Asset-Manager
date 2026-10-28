#!/usr/bin/env bash
# Helpers shared by bin/snapshot.sh and bin/dev.sh: start anvil in the background,
# wait for its RPC, stop it cleanly (SIGINT, so --dump-state is written).

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
STATE_DIR="${STATE_DIR:-.anvil}"
ANVIL_LOG="$STATE_DIR/anvil.log"
ANVIL_PID=""

require_tools() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
  done
}

require_port_free() {
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    echo "A node already answers on $RPC_URL: stop it first." >&2
    exit 1
  fi
}

# start_anvil <anvil args...>: log in $ANVIL_LOG, pid in ANVIL_PID
start_anvil() {
  mkdir -p "$STATE_DIR"
  anvil "$@" >"$ANVIL_LOG" 2>&1 &
  ANVIL_PID=$!
}

wait_rpc() {
  for _ in $(seq 1 60); do
    cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1 && return 0
    kill -0 "$ANVIL_PID" 2>/dev/null || { echo "anvil exited, see $ANVIL_LOG" >&2; exit 1; }
    sleep 0.5
  done
  echo "anvil did not answer on $RPC_URL within 30 s, see $ANVIL_LOG" >&2
  exit 1
}

stop_anvil() {
  if [ -n "$ANVIL_PID" ] && kill -0 "$ANVIL_PID" 2>/dev/null; then
    kill -INT "$ANVIL_PID"
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
  ANVIL_PID=""
}
