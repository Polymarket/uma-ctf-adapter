# UMA Conditional Tokens Binary Adapter SDK

This SDK is a lightweight wrapper around the `UmaConditionalTokensBinaryAdapter` contract.

### Usage

```ts
import { UmaBinaryAdapterClient } from "@polymarket/uma-binary-adapter-sdk";
const signer = new Wallet("0x" + process.env.KEY);
const adapter = new UmaBinaryAdapterClient(signer, 137);

// Initialize question
await adapter.initializeQuestion(
    questionID, 
    title, 
    description,
    outcomes, 
    resolutionTime, 
    rewardToken, 
    reward, 
    proposalBond, 
    { gasPrice: ethers.utils.parseUnits("100", 9) }
);

// Request resolution data
await adapter.requestResolutionData(questionID);

// Settle
await adapter.settle(questionID);

// View expected payout vector
await adapter.getExpectedPayouts(questionID);

//Report payouts
await adapter.reportPayouts(questionID);
```