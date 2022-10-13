#!/usr/bin/env bash

source .env

echo "Deploying UmaCtfAdapter..."

echo "Deploy args:
ConditionalTokensFramework: $CTF
Finder: $FINDER
"

OUTPUT="$(forge script Deploy \
    --private-key $PK \
    --rpc-url $RPC_URL \
    --json \
    --broadcast \
    -s "deploy(address,address)" $CTF $FINDER)"

ADAPTER=$(echo "$OUTPUT" | grep "{" | jq -r .returns.adapter.value)
echo "Adapter deployed: $ADAPTER"

echo "Complete!"
