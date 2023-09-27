# Polymarket UMA CTF Adapter

[![Version][version-badge]][version-link]
[![License][license-badge]][license-link]
[![Test][ci-badge]][ci-link]

[version-badge]: https://img.shields.io/github/v/release/polymarket/uma-ctf-adapter.svg?label=version
[version-link]: https://github.com/Polymarket/uma-ctf-adapter/releases
[license-badge]: https://img.shields.io/github/license/polymarket/uma-ctf-adapter
[license-link]: https://github.com/Polymarket/uma-ctf-adapter/blob/main/LICENSE.md
[ci-badge]: https://github.com/Polymarket/uma-ctf-adapter/workflows/Tests/badge.svg
[ci-link]: https://github.com/Polymarket/uma-ctf-adapter/actions/workflows/Tests.yaml

## Overview

This repository contains contracts used to resolve [Polymarket](https://polymarket.com/) prediction markets via UMA's [optimistic oracle](https://docs.umaproject.org/oracle/optimistic-oracle-interface).

## Architecture
![Contract Architecture](./docs/adapter.png)

The Adapter is an [oracle](https://github.com/Polymarket/conditional-tokens-contracts/blob/a927b5a52cf9ace712bf1b5fe1d92bf76399e692/contracts/ConditionalTokens.sol#L65) to [Conditional Tokens Framework(CTF)](https://docs.gnosis.io/conditionaltokens/) conditions, which Polymarket prediction markets are based on.

It fetches resolution data from UMA's Optmistic Oracle and resolves the condition based on said resolution data.

When a new market is deployed, it is `initialized`, meaning:
1) The market's parameters(ancillary data, request timestamp, reward token, reward, etc) are stored onchain
2) The market is [`prepared`](https://github.com/Polymarket/conditional-tokens-contracts/blob/a927b5a52cf9ace712bf1b5fe1d92bf76399e692/contracts/ConditionalTokens.sol#L65) on the CTF contract
3) A resolution data request is sent out to the Optimistic Oracle

UMA Proposers will then respond to the request and fetch resolution data offchain. If the resolution data is not disputed, the data will be available to the Adapter after a defined liveness period(currently about 2 hours).

The first time a request is disputed, the market is automatically `reset`, meaning, a new Optimistic Oracle request is sent out. This ensures that *obviously incorrect disputes do not slow down resolution of the market*.

If the request is disputed again, this indicates a more fundamental disagreement among proposers and the Optimistic Oracle falls back to UMA's [DVM](https://docs.umaproject.org/getting-started/oracle#umas-data-verification-mechanism) to come to agreement. The DVM will return data after a 48 - 72 hour period.

After resolution data is available, anyone can call `resolve` which resolves the market using the resolution data.


## Audit 

These contracts have been audited by OpenZeppelin and the report is available [here](./audit/Polymarket%20UMA%20Optimistic%20Oracle%20Adapter%20Audit.pdf).

## Deployments

See [Deployments](https://github.com/Polymarket/uma-ctf-adapter/releases)


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