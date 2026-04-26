const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const network = hre.network.name;
  const deploymentPath = path.join(__dirname, `../deployments/${network}.json`);
  
  if (!fs.existsSync(deploymentPath)) {
    throw new Error(`No deployment found for ${network}`);
  }
  
  const addresses = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  console.log("Verifying contracts on", network);

  try {
    await hre.run("verify:verify", {
      address: addresses.AgentRegistry,
      constructorArguments: [addresses.USDC],
    });
    console.log("AgentRegistry verified");
  } catch (e) {
    console.log("AgentRegistry:", e.message);
  }

  try {
    await hre.run("verify:verify", {
      address: addresses.PaymentIntent,
      constructorArguments: [addresses.AgentRegistry],
    });
    console.log("PaymentIntent verified");
  } catch (e) {
    console.log("PaymentIntent:", e.message);
  }

  try {
    await hre.run("verify:verify", {
      address: addresses.TaskEscrow,
      constructorArguments: [addresses.AgentRegistry],
    });
    console.log("TaskEscrow verified");
  } catch (e) {
    console.log("TaskEscrow:", e.message);
  }

  // LLMJuryVerifier needs extra args from deploy.js
  console.log("\nVerify LLMJuryVerifier manually with:");
  console.log(`npx hardhat verify --network ${network} ${addresses.LLMJuryVerifier} <router> <escrowAddr> <donId> <subId> '<source>'`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
