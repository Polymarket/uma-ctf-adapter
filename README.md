# Polymarket UMA CTF Adapter

![Github Actions](https://github.com/Polymarket/uma-conditional-tokens-adapter/workflows/Tests/badge.svg)
![Github Actions](https://github.com/Polymarket/uma-conditional-tokens-adapter/workflows/Lint/badge.svg)
[![Coverage](https://coveralls.io/repos/github/Polymarket/uma-conditional-tokens-adapter/badge.svg?branch=main)](https://coveralls.io/github/Polymarket/uma-conditional-tokens-adapter?branch=main)

## Overview

This repository contains contracts used to resolve [Polymarket](https://polymarket.com/) prediction markets via UMA's [optimistic oracle](https://docs.umaproject.org/oracle/optimistic-oracle-interface).

### [Architecture](./docs/Architecture.md)
![Contract Architecture](./docs/adapter.png)


### Deployments

See ./deploys.md


### Dependencies

Install dependencies with `yarn install`


### Compile


Compile the contracts with `yarn compile`

### Testing


Test the contracts with `yarn test`

### Coverage


Generate coverage reports with `yarn coverage`
