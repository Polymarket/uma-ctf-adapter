# UMA Conditional Tokens Binary Adapter SDK

This SDK is a lightweight wrapper around the `UmaConditionalTokensBinaryAdapter` contract.

### Usage

`import { UmaBinaryAdapterClient } from "@polymarket/uma-binary-adapter-sdk"`

`const adapter = new UmaBinaryAdapterClient(signer, 137);`

`await adapter.initializeQuestion(title, description, resolutionTime, rewardToken, reward)`