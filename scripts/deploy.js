const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  const network = hre.network.name;
  console.log("Network:", network);

  // 1. Deploy Mock USDC on testnet, or use real USDC address on mainnet
  let usdcAddress;
  if (network === "base-sepolia") {
    const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
    const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    await usdc.waitForDeployment();
    usdcAddress = await usdc.getAddress();
    console.log("MockUSDC deployed to:", usdcAddress);

    // Mint test USDC to deployer
    const mintTx = await usdc.mint(deployer.address, 10000e6); // 10k USDC
    await mintTx.wait();
    console.log("Minted 10k USDC to deployer");
  } else if (network === "base") {
    usdcAddress = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"; // Base mainnet USDC
    console.log("Using Base mainnet USDC:", usdcAddress);
  } else {
    throw new Error("Unsupported network");
  }

  // 2. Deploy AgentRegistry
  const AgentRegistry = await hre.ethers.getContractFactory("AgentRegistry");
  const registry = await AgentRegistry.deploy(usdcAddress);
  await registry.waitForDeployment();
  const registryAddr = await registry.getAddress();
  console.log("AgentRegistry deployed to:", registryAddr);

  // 3. Deploy PaymentIntent
  const PaymentIntent = await hre.ethers.getContractFactory("PaymentIntent");
  const paymentIntent = await PaymentIntent.deploy(registryAddr);
  await paymentIntent.waitForDeployment();
  const paymentIntentAddr = await paymentIntent.getAddress();
  console.log("PaymentIntent deployed to:", paymentIntentAddr);

  // 4. Deploy TaskEscrow
  const TaskEscrow = await hre.ethers.getContractFactory("TaskEscrow");
  const escrow = await TaskEscrow.deploy(registryAddr);
  await escrow.waitForDeployment();
  const escrowAddr = await escrow.getAddress();
  console.log("TaskEscrow deployed to:", escrowAddr);

  // 5. Deploy LLMJuryVerifier
  const router = network === "base-sepolia"
   ? "0xC22a79eBA640940ABB6d624568Fd2D99c1312576" // Base Sepolia Functions Router
    : "0xf9B8fc078197181C841c296C876945982fPhenom"; // Update for mainnet

  const donId = network === "base-sepolia"
   ? "0x66756e2d626173652d7365706f6c69612d310000000000000000" // fun-base-sepolia-1
    : "0x0"; // Update for mainnet

  const subscriptionId = process.env.FUNCTIONS_SUBSCRIPTION_ID || 0;
  const source = fs.readFileSync(path.join(__dirname, "../functions/jury.js"), "utf8");

  const LLMJuryVerifier = await hre.ethers.getContractFactory("LLMJuryVerifier");
  const jury = await LLMJuryVerifier.deploy(router, escrowAddr, donId, subscriptionId, source);
  await jury.waitForDeployment();
  const juryAddr = await jury.getAddress();
  console.log("LLMJuryVerifier deployed to:", juryAddr);

  // 6. Wire up contracts
  let tx = await escrow.setJuryVerifier(juryAddr);
  await tx.wait();
  console.log("JuryVerifier set in TaskEscrow");

  // Transfer ownership of registry to escrow so it can call recordTaskComplete/recordDispute
  tx = await registry.transferOwnership(escrowAddr);
  await tx.wait();
  console.log("AgentRegistry ownership transferred to TaskEscrow");

  // 7. Save addresses
  const addresses = {
    network,
    USDC: usdcAddress,
    AgentRegistry: registryAddr,
    PaymentIntent: paymentIntentAddr,
    TaskEscrow: escrowAddr,
    LLMJuryVerifier: juryAddr,
    deployer: deployer.address,
    timestamp: new Date().toISOString()
  };

  const deploymentsDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) fs.mkdirSync(deploymentsDir);
  fs.writeFileSync(
    path.join(deploymentsDir, `${network}.json`),
    JSON.stringify(addresses, null, 2)
  );

  console.log("\n=== Deployment Complete ===");
  console.log(JSON.stringify(addresses, null, 2));
  console.log("\nVerify with:");
  console.log(`npx hardhat verify --network ${network} ${registryAddr} ${usdcAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
