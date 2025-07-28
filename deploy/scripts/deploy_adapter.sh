#!/usr/bin/env bash

source .env

echo "Deploying UmaCtfAdapter..."

echo "Deploy args:
Admin: $ADMIN
ConditionalTokensFramework: $CTF
Finder: $FINDER
OptimisticOracle: $OPTIMISTIC_ORACLE
"

OUTPUT="$(forge script DeployAdapter \
    --private-key $PK \
    --rpc-url $RPC_URL \
    --json \
    --broadcast \
    -s "deployAdapter(address,address,address,address)" $ADMIN $CTF $FINDER $OPTIMISTIC_ORACLE)"

ADAPTER=$(echo "$OUTPUT" | grep "{" | jq -r .returns.adapter.value)
echo "Adapter deployed: $ADAPTER"

echo "Complete!"
