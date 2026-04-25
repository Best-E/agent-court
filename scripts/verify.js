const hre = require("hardhat");

async function main() {
  const addresses = {
    AgentRegistry: "0x...", // Fill after deploy
    TaskEscrow: "0x...",
    LLMJuryVerifier: "0x...",
    PaymentIntent: "0x..."
  };

  await hre.run("verify:verify", { address: addresses.AgentRegistry, constructorArguments: [] });
  await hre.run("verify:verify", { address: addresses.TaskEscrow, constructorArguments: [addresses.AgentRegistry] });
  await hre.run("verify:verify", { address: addresses.LLMJuryVerifier, constructorArguments: [addresses.TaskEscrow] });
  await hre.run("verify:verify", { address: addresses.PaymentIntent, constructorArguments: [addresses.AgentRegistry] });
}

main().catch(console.error);
