# Polymarket UMA CTF Adapter

![Github Actions](https://github.com/Polymarket/uma-conditional-tokens-adapter/workflows/Tests/badge.svg)

## Overview

This repository contains contracts used to resolve [Polymarket](https://polymarket.com/) prediction markets via UMA's [optimistic oracle](https://docs.umaproject.org/oracle/optimistic-oracle-interface).

## Architecture
![Contract Architecture](./docs/adapter.png)

The Adapter is an [oracle](https://github.com/Polymarket/conditional-tokens-contracts/blob/a927b5a52cf9ace712bf1b5fe1d92bf76399e692/contracts/ConditionalTokens.sol#L65) to [Conditional Tokens Framework(CTF)](https://docs.gnosis.io/conditionaltokens/) conditions, which Polymarket prediction markets are based on.

It fetches resolution data from UMA's Optmistic Oracle and resolves the condition based on said resolution data.

When a new market is deployed, it is `initialized`, meaning:
1) The market's parameters(request timestamp, reward, etc) are stored onchain
2) The market is [`prepared`](https://github.com/Polymarket/conditional-tokens-contracts/blob/a927b5a52cf9ace712bf1b5fe1d92bf76399e692/contracts/ConditionalTokens.sol#L65) on the CTF contract
3) A resolution data request is sent out to the Optimistic Oracle

UMA Proposers will then respond to the request and fetch resolution data offchain. If the resolution data is not disputed, the data will be available to the Adapter after a defined liveness period(currently about 2 hours). 

If the proposal is disputed, UMA's [DVM](https://docs.umaproject.org/getting-started/oracle#umas-data-verification-mechanism) is the fallback and will return data after a 48 - 72 hour period.

After resolution data is available, anyone can call `resolve` which resolves the market using the resolution data.


## Deployments

| Network          | Address                                                                           |
| ---------------- | --------------------------------------------------------------------------------- |
| Polygon          |[0x6A9D222616C90FcA5754cd1333cFD9b7fb6a4F74](https://polygonscan.com/address/0x6A9D222616C90FcA5754cd1333cFD9b7fb6a4F74)|
| Mumbai           |[0x6A9D222616C90FcA5754cd1333cFD9b7fb6a4F74](https://mumbai.polygonscan.com/address/0x6A9D222616C90FcA5754cd1333cFD9b7fb6a4F74)|


## Development

Clone the repo: `git clone https://github.com/Polymarket/uma-ctf-adapter.git --recurse-submodules`

---

### Set-up

Install [Foundry](https://github.com/foundry-rs/foundry/).

Foundry has daily updates, run `foundryup` to update `forge` and `cast`.

To install/update forge dependencies: `forge update`

To build contracts: `forge build`

---

### Testing

To run all tests: `forge test`

Set `-vvv` to see a stack trace for a failed test.