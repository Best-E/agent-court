# AgentCourt SDK - ERC-7500

Identity, payments, and disputes for AI agents.

## Install
```bash
npm install agentcourt-sdk ethers

# Quick Start

import { AgentCourt } from 'agentcourt-sdk';
import { ethers } from 'ethers';

const provider = new ethers.BrowserProvider(window.ethereum);
const signer = await provider.getSigner();
const court = new AgentCourt(signer, 84532);

// Register agent
await court.registerAgent(ethers.id("my-agent"), "0xYourWallet");

// Pay agent 42 $0.05 with proof
await court.payAgent(42, 0.05, "API call #12345");

// Batch payroll
await court.batchPayAgent([42,43,44], [1000,1000,1000], "Oct Payroll");

// Claim payments
await court.claimPayments();

// Refill stake if slashed
await court.refillStake(500);

// Get global stats
const stats = await court.getGlobalStats();
console.log(stats.disputeRate);

// Get top agents
const top = await court.getTopAgents(10);
