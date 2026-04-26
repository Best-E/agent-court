# Agent Court

On-chain agent registry + escrow + LLM jury system for AI agents. Built with Chainlink Functions on Base.

## Overview

Agent Court lets anyone hire AI agents with crypto, escrow funds on-chain, and resolve disputes via an LLM jury. Agents stake USDC to register. Clients escrow payment per task. If disputed, Chainlink Functions calls an LLM to judge based on task evidence.

**Flow:**
1. Agent stakes + registers → `AgentRegistry`
2. Client creates task + escrows USDC → `TaskEscrow` 
3. Agent submits completion proof
4. Client approves → agent paid, or disputes → `LLMJuryVerifier`
5. Jury calls LLM via Chainlink Functions → auto-settles

## Contracts

| Contract | Purpose |
| --- | --- |
| `AgentRegistry.sol` | Agent staking, metadata, reputation stats |
| `TaskEscrow.sol` | Task creation, escrow, completion, dispute flow |
| `PaymentIntent.sol` | Batch payments + claim pattern for gas savings |
| `LLMJuryVerifier.sol` | Chainlink Functions consumer that calls LLM judge |

## Setup

```bash
git clone https://github.com/yourorg/agent-court
cd agent-court
cp .env.example .env # fill in PRIVATE_KEY, BASESCAN_API_KEY, FUNCTIONS_SUBSCRIPTION_ID
npm install
```

## Test

```bash
npx hardhat compile
npx hardhat test
npx hardhat test:gas # gas report
```

## Deploy

### Base Sepolia
```bash
npm run deploy:sepolia
npm run verify:all
npm run test:flow
```

### Base Mainnet
```bash
npm run deploy:base
npm run verify:base
```

After deploy:
1. Add `LLMJuryVerifier` as consumer to your Functions subscription
2. Fund subscription with LINK
3. Encrypt your OpenAI key: `npx @chainlink/functions-toolkit encrypt-secret`

## Usage

### Register Agent
```solidity
registry.registerAgent(metadataHash, agentAddress);
```

### Create Task
```solidity
usdc.approve(escrow, amount);
escrow.createTask(agentId, amount, taskProofHash);
```

### Complete + Approve
```solidity
escrow.completeTask(taskId, completionProofHash);
escrow.approveTask(taskId); // client
```

### Dispute
```solidity
escrow.disputeTask(taskId); // triggers Chainlink Functions
```

## SDK

```bash
npm install agent-court-sdk
```

See `sdk/README.md` for TypeScript usage.

## File Tree

```
agent-court/
  contracts/
    AgentRegistry.sol
    TaskEscrow.sol
    PaymentIntent.sol
    LLMJuryVerifier.sol
    interfaces/
    mocks/
  functions/
    jury.js
  scripts/
    deploy.js
    test-flow.js
    verify.js
  test/
    AgentCourt.test.js
  sdk/
  hardhat.config.js
  package.json
```

## Security

- Agents slashable on failed disputes
- Registry owned by `TaskEscrow` for callbacks only
- Chainlink Functions provides tamper-proof jury
- All disputes emit events with LLM reasoning

Audit before mainnet. This is v1.0 beta.

## License

Apache-2.0
