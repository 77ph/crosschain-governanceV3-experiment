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
