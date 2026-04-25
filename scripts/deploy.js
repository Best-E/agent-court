const { ethers, run } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("Deploying AgentCourt to Base Sepolia...");
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const USDC_ADDRESS = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";

  console.log("\n1. Deploying AgentRegistry...");
  const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
  const registry = await AgentRegistry.deploy(USDC_ADDRESS);
  await registry.waitForDeployment();
  const registryAddr = await registry.getAddress();
  console.log("AgentRegistry deployed to:", registryAddr);

  console.log("\n2. Deploying TaskEscrow...");
  const TaskEscrow = await ethers.getContractFactory("TaskEscrow");
  const escrow = await TaskEscrow.deploy(USDC_ADDRESS, registryAddr);
  await escrow.waitForDeployment();
  const escrowAddr = await escrow.getAddress();
  console.log("TaskEscrow deployed to:", escrowAddr);

  console.log("\n3. Deploying LLMJuryVerifier...");
  const SUBSCRIPTION_ID = process.env.CHAINLINK_SUB_ID || 0;
  const LLMJuryVerifier = await ethers.getContractFactory("LLMJuryVerifier");
  const jury = await LLMJuryVerifier.deploy(escrowAddr, SUBSCRIPTION_ID);
  await jury.waitForDeployment();
  const juryAddr = await jury.getAddress();
  console.log("LLMJuryVerifier deployed to:", juryAddr);

  console.log("\n4. Initializing AgentRegistry...");
  const initTx = await registry.initialize(escrowAddr, juryAddr);
  await initTx.wait();
  console.log("Registry initialized with Escrow + Jury");

  console.log("\n5. Verifying contracts on Basescan...");
  console.log("Waiting 30s for Basescan to index...");
  await new Promise(r => setTimeout(r, 30000));

  try {
    await run("verify:verify", { address: registryAddr, constructorArguments: [USDC_ADDRESS] });
    console.log("AgentRegistry verified");
  } catch (e) { console.log("AgentRegistry verify failed:", e.message); }

  try {
    await run("verify:verify", { address: escrowAddr, constructorArguments: [USDC_ADDRESS, registryAddr] });
    console.log("TaskEscrow verified");
  } catch (e) { console.log("TaskEscrow verify failed:", e.message); }

  try {
    await run("verify:verify", { address: juryAddr, constructorArguments: [escrowAddr, SUBSCRIPTION_ID] });
    console.log("LLMJuryVerifier verified");
  } catch (e) { console.log("LLMJuryVerifier verify failed:", e.message); }

  console.log("\n=== DEPLOYMENT COMPLETE ===");
  console.log("Network: Base Sepolia");
  console.log("AgentRegistry:", registryAddr);
  console.log("TaskEscrow: ", escrowAddr);
  console.log("LLMJury: ", juryAddr);
  console.log("USDC Used: ", USDC_ADDRESS);
  console.log("\nBasescan Links:");
  console.log(`https://sepolia.basescan.org/address/${registryAddr}`);
  console.log(`https://sepolia.basescan.org/address/${escrowAddr}`);
  console.log(`https://sepolia.basescan.org/address/${juryAddr}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
