const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer, client, agent] = await hre.ethers.getSigners();
  const network = hre.network.name;
  
  console.log("Running e2e flow on:", network);
  console.log("Deployer:", deployer.address);

  // Load deployed addresses
  const deploymentPath = path.join(__dirname, `../deployments/${network}.json`);
  if (!fs.existsSync(deploymentPath)) {
    throw new Error(`No deployment found for ${network}. Run deploy.js first.`);
  }
  const addresses = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  console.log("Loaded addresses:", addresses);

  const usdc = await hre.ethers.getContractAt("MockERC20", addresses.USDC);
  const registry = await hre.ethers.getContractAt("AgentRegistry", addresses.AgentRegistry);
  const escrow = await hre.ethers.getContractAt("TaskEscrow", addresses.TaskEscrow);

  const STAKE = 500n * 10n ** 6n;
  const amount = 100n * 10n ** 6n;

  // 1. Register agent if not already
  const agentId = await registry.ownerToId(agent.address);
  if (agentId == 0) {
    console.log("Registering agent...");
    await usdc.mint(agent.address, STAKE);
    await usdc.connect(agent).approve(addresses.AgentRegistry, STAKE);
    const metadataHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test-agent"));
    await registry.connect(agent).registerAgent(metadataHash, agent.address);
    console.log("Agent registered. ID:", await registry.ownerToId(agent.address));
  }

  // 2. Register client if not already  
  const clientId = await registry.ownerToId(client.address);
  if (clientId == 0) {
    console.log("Registering client...");
    await usdc.mint(client.address, STAKE);
    await usdc.connect(client).approve(addresses.AgentRegistry, STAKE);
    await registry.connect(client).registerAgent(hre.ethers.keccak256(hre.ethers.toUtf8Bytes("client")), client.address);
    console.log("Client registered. ID:", await registry.ownerToId(client.address));
  }

  // 3. Create task
  console.log("Creating task...");
  await usdc.mint(client.address, amount);
  await usdc.connect(client).approve(addresses.TaskEscrow, amount);
  const taskId = await escrow.taskCounter() + 1n;
  const proofHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("ipfs://task-desc"));
  
  await escrow.connect(client).createTask(
    await registry.ownerToId(agent.address), 
    amount, 
    proofHash
  );
  console.log("Task created. ID:", taskId.toString());

  // 4. Agent completes
  console.log("Agent completing task...");
  const completeProof = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("ipfs://completion"));
  await escrow.connect(agent).completeTask(taskId, completeProof);
  
  // 5. Client approves
  console.log("Client approving...");
  const balBefore = await usdc.balanceOf(agent.address);
  await escrow.connect(client).approveTask(taskId);
  const balAfter = await usdc.balanceOf(agent.address);
  
  console.log("Agent paid:", hre.ethers.formatUnits(balAfter - balBefore, 6), "USDC");
  console.log("Flow complete ✓");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
