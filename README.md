# UMA Conditional Tokens Binary Adapter

![Github Actions](https://github.com/Polymarket/uma-conditional-tokens-adapter/workflows/Tests/badge.svg)

## Overview

This repo contains code used to resolve Polymarket prediction markets via UMA's [optimistic oracle](https://docs.umaproject.org/oracle/optimistic-oracle-interface).


### Dependencies
- cd into `./packages/contracts/`

- Install dependencies with `yarn install`

### Compile

Compile the contracts with `yarn compile`

### SDK

[Adapter SDK README](./packages/sdk/README.md)

```ts
import { UmaBinaryAdapterClient } from "@polymarket/uma-binary-adapter-sdk";
const signer = new Wallet("0x" + process.env.KEY);
const adapter = new UmaBinaryAdapterClient(signer, 137);

// Initialize question
await adapter.initializeQuestion(
    questionID, 
    title, 
    description, 
    resolutionTime, 
    rewardToken, 
    reward, 
    proposalBond, 
    { gasPrice: ethers.utils.parseUnits("100", 9) }
);

// Request resolution data
await adapter.requestResolutionData(questionID);

// Report payouts
await adapter.reportPayouts(questionID);

```