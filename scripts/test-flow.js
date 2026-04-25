const { ethers } = require("hardhat");

async function main() {
  const [deployer, agentA, agentB] = await ethers.getSigners();

  // Replace with your deployed addresses after running deploy.js
  const REGISTRY_ADDR = "0x..."; // AgentRegistry
  const ESCROW_ADDR = "0x..."; // TaskEscrow
  const USDC_ADDR = "0x036CbD53842c5426634e7929541eC2318f3dCF7e"; // Base Sepolia USDC

  const usdc = await ethers.getContractAt("MockERC20", USDC_ADDR);
  const registry = await ethers.getContractAt("AgentRegistry", REGISTRY_ADDR);
  const escrow = await ethers.getContractAt("TaskEscrow", ESCROW_ADDR);

  console.log("Minting test USDC...");
  await usdc.mint(agentA.address, ethers.parseUnits("1000", 6));
  await usdc.mint(agentB.address, ethers.parseUnits("1000", 6));

  console.log("Registering Agent A as Payer...");
  await usdc.connect(agentA).approve(REGISTRY_ADDR, ethers.parseUnits("500", 6));
  await registry.connect(agentA).registerAgent(ethers.id("AgentA"), agentA.address);

  console.log("Registering Agent B as Worker...");
  await usdc.connect(agentB).approve(REGISTRY_ADDR, ethers.parseUnits("500", 6));
  await registry.connect(agentB).registerAgent(ethers.id("AgentB"), agentB.address);

  const agentAData = await registry.getAgentByOwner(agentA.address);
  const agentBData = await registry.getAgentByOwner(agentB.address);

  console.log("Agent A ID:", agentAData.id.toString(), "Stake:", agentAData.stake.toString());
  console.log("Agent B ID:", agentBData.id.toString(), "Stake:", agentBData.stake.toString());
  console.log("Success. Agents ready on Base Sepolia.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
