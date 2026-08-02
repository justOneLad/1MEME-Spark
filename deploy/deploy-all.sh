#!/usr/bin/env bash
set -euo pipefail

# Runs DeploySparkUpgradeable then DeploySparkGo in one command. Each script sends its
# transactions one at a time with a 5s real-world pause after every one (vm.sleep, see the
# scripts themselves); this wrapper adds the same pause between the two scripts.
#
# --skip-simulation: most public/shared BSC RPC endpoints fail forge's second on-chain
# verification pass ("missing trie node" / "historical state not available") even though the
# first simulation succeeds — skipping it and broadcasting directly is what actually worked.

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <private-key> [rpc-url]" >&2
  exit 1
fi

PRIVATE_KEY="$1"
RPC_URL="${2:-${BSC_RPC_URL:-https://binance.nodereal.io}}"

cd "$(dirname "$0")"

forge script script/DeploySparkUpgradeable.s.sol:DeploySparkUpgradeable \
  --rpc-url "$RPC_URL" --broadcast --slow --skip-simulation --private-key "$PRIVATE_KEY"

sleep 5

forge script script/DeploySparkGo.s.sol:DeploySparkGo \
  --rpc-url "$RPC_URL" --broadcast --slow --skip-simulation --private-key "$PRIVATE_KEY"
