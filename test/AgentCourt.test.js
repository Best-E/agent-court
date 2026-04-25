const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ERC-7500 v1.0", function () {
  let registry, escrow, jury, payment, usdc;
  let owner, agent1, agent2, agent3;

  beforeEach(async function () {
    [owner, agent1, agent2, agent3] = await ethers.getSigners();

    const MockUSDC = await ethers.getContractFactory("MockERC20");
    usdc = await MockUSDC.deploy("USDC", "USDC", 6);

    const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
    registry = await AgentRegistry.deploy();

    const TaskEscrow = await ethers.getContractFactory("TaskEscrow");
    escrow = await TaskEscrow.deploy(await registry.getAddress());

    const LLMJuryVerifier = await ethers.getContractFactory("LLMJuryVerifier");
    jury = await LLMJuryVerifier.deploy(await escrow.getAddress());

    const PaymentIntent = await ethers.getContractFactory("PaymentIntent");
    payment = await PaymentIntent.deploy(await registry.getAddress());
  });

  it("Should register agent", async function () {
    await usdc.mint(agent1.address, 500e6);
    await usdc.connect(agent1).approve(await registry.getAddress(), 500e6);
    await registry.connect(agent1).registerAgent(ethers.id("test"), agent1.address);
    const agent = await registry.getAgent(1);
    expect(agent.active).to.equal(true);
    expect(agent.id).to.equal(1);
  });

  it("Should allow stake refill and reactivate", async function () {
    await usdc.mint(agent1.address, 1000e6);
    await usdc.connect(agent1).approve(await registry.getAddress(), 1000e6);
    await registry.connect(agent1).registerAgent(ethers.id("test"), agent1.address);

    await registry.slash(1, 500e6, "test");
    let agent = await registry.getAgent(1);
    expect(agent.active).to.equal(false);

    await usdc.connect(agent1).approve(await registry.getAddress(), 500e6);
    await registry.connect(agent1).refillStake(500e6);
    agent = await registry.getAgent(1);
    expect(agent.active).to.equal(true);
    expect(agent.id).to.equal(1);
  });

  it("Should allow $0.001 payment", async function () {
    await usdc.mint(agent1.address, 500e6);
    await usdc.connect(agent1).approve(await registry.getAddress(), 500e6);
    await registry.connect(agent1).registerAgent(ethers.id("a1"), agent1.address);

    await usdc.mint(agent2.address, 500e6);
    await usdc.connect(agent2).approve(await registry.getAddress(), 500e6);
    await registry.connect(agent2).registerAgent(ethers.id("a2"), agent2.address);

    await usdc.mint(agent1.address, 1000);
    await usdc.connect(agent1).approve(await payment.getAddress(), 1000);
    await payment.connect(agent1).pay(2, 1000, ethers.id("micro"));
    expect(await payment.pendingClaims(2)).to.equal(1000);
  });

  it("Should batch pay 3 agents", async function () {
    await usdc.mint(agent1.address, 500e6);
    await usdc.connect(agent1).approve(await registry.getAddress(), 500e6);
    await registry.connect(agent1).registerAgent(ethers.id("a1"), agent1.address);

    await usdc.mint(agent2.address, 500e6);
    await usdc.connect(agent2).approve(await registry.getAddress(), 500e6);
    await registry.connect(agent2).registerAgent(ethers.id("a2"), agent2.address);

    await usdc.mint(agent3.address, 500e6);
    await usdc.connect(agent3).approve(await registry.getAddress(), 500e6);
    await registry.connect(agent3).registerAgent(ethers.id("a3"), agent3.address);

    await usdc.mint(agent1.address, 3000);
    await usdc.connect(agent1).approve(await payment.getAddress(), 3000);
    await payment.connect(agent1).batchPay([2,3], [1000,1000], ethers.id("batch"));
    expect(await payment.pendingClaims(2)).to.equal(1000);
    expect(await payment.pendingClaims(3)).to.equal(1000);
  });

  it("Should revert duplicate in batch", async function () {
    await expect(
      payment.batchPay([1,1], [1000,1000], ethers.id("hack"))
    ).to.be.revertedWithCustomError(payment, "DuplicateRecipient");
  });

  it("Should return global stats", async function () {
    const stats = await registry.getStats();
    expect(stats.totalAgents).to.equal(0);
    expect(stats.activeAgents).to.equal(0);
  });

  it("Should track agent stats", async function () {
    await usdc.mint(agent1.address, 500e6);
    await usdc.connect(agent1).approve(await registry.getAddress(), 500e6);
    await registry.connect(agent1).registerAgent(ethers.id("a1"), agent1.address);

    await registry.recordTaskComplete(1, 1000e6);
    const agent = await registry.getAgent(1);
    expect(agent.tasksCompleted).to.equal(1);
    expect(agent.totalEarned).to.equal(1000e6);
  });
});
