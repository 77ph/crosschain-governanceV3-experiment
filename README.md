# Crosschain Governance PoC (Foundry + Wormhole)

This project demonstrates a proof-of-concept for a crosschain governance system, inspired by Aave Governance V3.

## Components

- `src/` – Contracts: `VotingMachine`, `GovernorRelay`
- `cli/` – Node.js CLI tools for proposal, voting, and relaying
- `test/` – Put your Foundry tests here
- `script/` – Optional Foundry deployment scripts

## Quick Start

```bash
forge build
cd cli
node governor-cli.js --help
```

## Governance Flow

1. Propose on L1 (Ethereum)
2. Snapshot block recorded
3. Votes cast on L2 (e.g., Polygon) using storage proofs
4. VotingMachine aggregates and relays result via Wormhole
5. GovernorRelay on L1 finalizes result and enables execution

## Crosschain Governance PoC — CLI Reference

### 🛠 CLI Commands Overview

This repository includes a CLI tool (`governor-cli.js`) that supports the entire Governance V3 crosschain flow.

#### 🔧 Available Commands

| Command               | Description |
|-----------------------|-------------|
| `propose`             | Create a new proposal on the Governor contract (L1). Requires targets, values, calldata, and description. |
| `get-snapshot`        | Query the snapshot block number (`proposalSnapshot`) for a given proposal ID. |
| `publish-root`        | Submit the storage root of a token contract from L1 using `eth_getProof`, to initialize verification in the VotingMachine. |
| `vote`                | Submit a vote with proof from L1 state (uses `voteWithProof`). Requires snapshot block, voter address, slot, and proof. |
| `relay-result`        | Submit the total aggregated result (internally tracked by VotingMachine) to L1 via Wormhole or relayer. |
| `aggregate-votes`     | Off-chain utility to sum up voting weights per address for a given proposal. Useful for auditing and verification. |

#### 💡 Usage Example

```bash
node governor-cli.js propose --governor 0x... --targets 0x... --values 0 --calldatas 0x... --description "Enable crosschain voting"

node governor-cli.js get-snapshot --governor 0x... --proposal-id 1

node governor-cli.js publish-root --token 0x... --block 12345678 --voting-machine 0x...

node governor-cli.js vote --proposal-id 1 --snapshot-block 12345678 --token 0x... --voter 0x... --slot 42 --proof 0x... --voting-machine 0x...

node governor-cli.js aggregate-votes --proposal-id 1 --voting-machine 0x... --voters 0xabc...,0xdef...

node governor-cli.js relay-result --proposal-id 1 --voting-machine 0x... --gas-limit 500000 --eth 0.05
```
