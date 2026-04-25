const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("AgentCourt ERC-7500", function () {
  let usdc, registry, escrow, jury, owner, agentA, agentB, attacker;
  const USDC_DECIMALS = 6;
  const MIN_STAKE = ethers.parseUnits("500", USDC_DECIMALS);
  const TASK_AMOUNT = ethers.parseUnits("50", USDC_DECIMALS);
  const SPEC_HASH = ethers.id("Research BTC 2020-2024, 5 pages");
  const RESULT_HASH = ethers.id("Here is the research PDF");
  const DEFENSE_HASH = ethers.id("Spec asked for summary, I gave 5 pages");

  beforeEach(async function () {
    [owner, agentA, agentB, attacker] = await ethers.getSigners();
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    usdc = await MockUSDC.deploy("USDC", "USDC", USDC_DECIMALS);
    await usdc.mint(agentA.address, ethers.parseUnits("1000", USDC_DECIMALS));
    await usdc.mint(agentB.address, ethers.parseUnits("1000", USDC_DECIMALS));
    await usdc.mint(attacker.address, ethers.parseUnits("1000", USDC_DECIMALS));
    const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
    registry = await AgentRegistry.deploy(await usdc.getAddress());
    const TaskEscrow = await ethers.getContractFactory("TaskEscrow");
    escrow = await TaskEscrow.deploy(await usdc.getAddress(), await registry.getAddress());
    const MockJury = await ethers.getContractFactory("MockLLMJuryVerifier");
    jury = await MockJury.deploy(await escrow.getAddress());
    await registry.initialize(await escrow.getAddress(), owner.address);
    await usdc.connect(agentA).approve(await registry.getAddress(), MIN_STAKE);
    await registry.connect(agentA).registerAgent(ethers.id("AgentA"), agentA.address);
    await usdc.connect(agentB).approve(await registry.getAddress(), MIN_STAKE);
    await registry.connect(agentB).registerAgent(ethers.id("AgentB"), agentB.address);
  });

  describe("AgentRegistry", function () {
    it("Should register agent with $500 stake", async function () {
      const agent = await registry.getAgentByOwner(agentA.address);
      expect(agent.stake).to.equal(MIN_STAKE);
      expect(agent.score).to.equal(500);
      expect(agent.active).to.equal(true);
    });
    it("CertiK Fix #2: Should lock stake on submitProof", async function () {
      const taskId = await createAndSubmitTask();
      const agent = await registry.getAgent(2);
      expect(agent.stakeLockedUntil).to.be.gt(await time.latest());
    });
    it("Should prevent withdraw during stake lock", async function () {
      await createAndSubmitTask();
      await expect(registry.connect(agentB).withdrawStake(ethers.parseUnits("1", USDC_DECIMALS))).to.be.revertedWithCustomError(registry, "StakeLocked");
    });
  });

  describe("TaskEscrow - Happy Path", function () {
    it("Should create task, submit, auto-release after 24h", async function () {
      await usdc.connect(agentA).approve(await escrow.getAddress(), TASK_AMOUNT * 2n);
      await escrow.connect(agentA).createTask(2, TASK_AMOUNT, SPEC_HASH, await jury.getAddress(), (await time.latest()) + 3600);
      const taskId = 1;
      await escrow.connect(agentB).submitProof(taskId, RESULT_HASH);
      await time.increase(24 * 3600 + 1);
      await escrow.release(taskId);
      const balance = await usdc.balanceOf(agentB.address);
      expect(balance).to.equal(ethers.parseUnits("1500", USDC_DECIMALS));
    });
  });

  describe("TaskEscrow - Dispute Flow", function () {
    it("Should allow 24h defense window and count defense", async function () {
      const taskId = await createAndSubmitTask();
      await escrow.connect(agentA).dispute(taskId, ethers.toUtf8Bytes("Bad work"), { value: ethers.parseEther("10") });
      await escrow.connect(agentB).submitDefense(taskId, ethers.toUtf8Bytes(DEFENSE_HASH));
      const task = await escrow.getTask(taskId);
      expect(task.defenseHash).to.not.equal(ethers.ZeroHash);
      expect
