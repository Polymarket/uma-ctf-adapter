# UMA Conditional Tokens Binary Adapter

![Github Actions](https://github.com/Polymarket/uma-conditional-tokens-adapter/workflows/Tests/badge.svg)
![Github Actions](https://github.com/Polymarket/uma-conditional-tokens-adapter/workflows/Lint/badge.svg)

## Overview

This repository contains code used to resolve [Polymarket](https://polymarket.com/) prediction markets via UMA's [optimistic oracle](https://docs.umaproject.org/oracle/optimistic-oracle-interface).

### [Architecture](./docs/Architecture.md)
![Contract Architecture](./docs/adapter.png)


### Deployments

| Network          | Address                                                                           |
| ---------------- | --------------------------------------------------------------------------------- |
| Polygon          | [0xCB1822859cEF82Cd2Eb4E6276C7916e692995130](https://polygonscan.com/address/0xCB1822859cEF82Cd2Eb4E6276C7916e692995130)|
| Mumbai           | [0xCB1822859cEF82Cd2Eb4E6276C7916e692995130](https://mumbai.polygonscan.com/address/0xCB1822859cEF82Cd2Eb4E6276C7916e692995130)|


### Dependencies

Install dependencies with `yarn install`


### Compile

Compile the contracts with `yarn compile`


### Testing

Test the contracts with `yarn test`

### Coverage

Generate coverage reports with `yarn coverage`
