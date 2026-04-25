const hre = require("hardhat");

async function main() {
  console.log("Deploying ERC-7500 v1.0 to Base Sepolia...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // 1. AgentRegistry
  console.log("\n1. Deploying AgentRegistry...");
  const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
  const registry = await AgentRegistry.deploy();
  await registry.waitForDeployment();
  const registryAddr = await registry.getAddress();
  console.log("AgentRegistry:", registryAddr);

  // 2. TaskEscrow
  console.log("\n2. Deploying TaskEscrow...");
  const TaskEscrow = await ethers.getContractFactory("TaskEscrow");
  const escrow = await TaskEscrow.deploy(registryAddr);
  await escrow.waitForDeployment();
  const escrowAddr = await escrow.getAddress();
  console.log("TaskEscrow:", escrowAddr);

  // 3. LLMJuryVerifier
  console.log("\n3. Deploying LLMJuryVerifier...");
  const LLMJuryVerifier = await ethers.getContractFactory("LLMJuryVerifier");
  const jury = await LLMJuryVerifier.deploy(escrowAddr);
  await jury.waitForDeployment();
  const juryAddr = await jury.getAddress();
  console.log("LLMJuryVerifier:", juryAddr);

  // 4. PaymentIntent
  console.log("\n4. Deploying PaymentIntent...");
  const PaymentIntent = await ethers.getContractFactory("PaymentIntent");
  const payment = await PaymentIntent.deploy(registryAddr);
  await payment.waitForDeployment();
  const paymentAddr = await payment.getAddress();
  console.log("PaymentIntent:", paymentAddr);

  console.log("\n=== DEPLOYMENT COMPLETE ===");
  console.log("AgentRegistry:", registryAddr);
  console.log("TaskEscrow:", escrowAddr);
  console.log("LLMJuryVerifier:", juryAddr);
  console.log("PaymentIntent:", paymentAddr);
  console.log("\nUpdate sdk/index.js ADDRESSES with these values");

  console.log("\nVerifying contracts...");
  await new Promise(r => setTimeout(r, 30000));

  try {
    await hre.run("verify:verify", { address: registryAddr, constructorArguments: [] });
    console.log("AgentRegistry verified");
  } catch (e) { console.log("Registry verify:", e.message); }

  try {
    await hre.run("verify:verify", { address: escrowAddr, constructorArguments: [registryAddr] });
    console.log("TaskEscrow verified");
  } catch (e) { console.log("Escrow verify:", e.message); }

  try {
    await hre.run("verify:verify", { address: juryAddr, constructorArguments: [escrowAddr] });
    console.log("LLMJuryVerifier verified");
  } catch (e) { console.log("Jury verify:", e.message); }

  try {
    await hre.run("verify:verify", { address: paymentAddr, constructorArguments: [registryAddr] });
    console.log("PaymentIntent verified");
  } catch (e) { console.log("Payment verify:", e.message); }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
