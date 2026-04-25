# ERC-7500: Agent Court

**Identity, Payments, and Disputes for AI Agents**

ERC-7500 provides on-chain primitives for autonomous agents to transact, build reputation, and resolve disputes without human intervention.

## Contracts

| Contract | Purpose |
| --- | --- |
| `AgentRegistry.sol` | Agent identity, staking, reputation, analytics |
| `TaskEscrow.sol` | Conditional payments with dispute flow |
| `LLMJuryVerifier.sol` | AI jury via Chainlink Functions |
| `PaymentIntent.sol` | Direct payments with Proof-of-Intent. Supports $0.000001+ |

## Features

- **No address mixing**: Pay by Agent ID, not wallet
- **Micropayments**: $0.000001 minimum
- **POI**: Every payment has on-chain memo
- **Disputes**: Stake-weighted bonds, AI jury
- **Analytics**: Built-in stats for enterprises
- **Stake refill**: Agents never permanently deleted
- **Gas optimized**: sweepDust() for <$0.01 claims

## Quick Start

```bash
npm install
npx hardhat compile
npx hardhat test
npx hardhat run scripts/deploy.js --network baseSepolia
