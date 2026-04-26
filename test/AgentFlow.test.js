const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentFlow", function () {
  let usdc, registry, paymentIntent, escrow, jury;
  let owner, client, agent, juryAddr;
  const STAKE = 500n * 10n ** 6n; // 500 USDC
  const metadataHash = ethers.keccak256(ethers.toUtf8Bytes("agent-v1"));

  beforeEach(async function () {
    [owner, client, agent, juryAddr] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", 6);

    const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
    registry = await AgentRegistry.deploy(await usdc.getAddress());

    const PaymentIntent = await ethers.getContractFactory("PaymentIntent");
    paymentIntent = await PaymentIntent.deploy(await registry.getAddress());

    const TaskEscrow = await ethers.getContractFactory("TaskEscrow");
    escrow = await TaskEscrow.deploy(await registry.getAddress());

    // Mock jury for testing
    await escrow.setJuryVerifier(juryAddr.address);
    
    // Transfer registry ownership to escrow for callbacks
    await registry.transferOwnership(await escrow.getAddress());

    // Fund accounts
    await usdc.mint(client.address, 10000n * 10n ** 6n);
    await usdc.mint(agent.address, 10000n * 10n ** 6n);

    await usdc.connect(client).approve(await registry.getAddress(), STAKE);
    await usdc.connect(agent).approve(await registry.getAddress(), STAKE);
  });

  it("Full happy path: register -> create -> complete -> approve", async function () {
    // 1. Register client + agent
    await registry.connect(client).registerAgent(ethers.keccak256(ethers.toUtf8Bytes("client")), client.address);
    await registry.connect(agent).registerAgent(metadataHash, agent.address);

    const clientId = await registry.ownerToId(client.address);
    const agentId = await registry.ownerToId(agent.address);

    // 2. Client creates task for 100 USDC
    const amount = 100n * 10n ** 6n;
    const proofHash = ethers.keccak256(ethers.toUtf8Bytes("task-proof"));
    await usdc.connect(client).approve(await escrow.getAddress(), amount);
    
    const tx = await escrow.connect(client).createTask(agentId, amount, proofHash);
    const receipt = await tx.wait();
    const taskId = 1n;

    expect(await escrow.escrowedAmounts(taskId)).to.equal(amount);

    // 3. Agent completes task
    const completeProof = ethers.keccak256(ethers.toUtf8Bytes("completion-proof"));
    await escrow.connect(agent).completeTask(taskId, completeProof);

    let task = await escrow.getTask(taskId);
    expect(task.status).to.equal(1); // Completed

    // 4. Client approves
    const agentBalBefore = await usdc.balanceOf(agent.address);
    await escrow.connect(client).approveTask(taskId);

    task = await escrow.getTask(taskId);
    expect(task.status).to.equal(3); // Resolved
    expect(await usdc.balanceOf(agent.address)).to.equal(agentBalBefore + amount);

    // 5. Check registry stats updated
    const agentData = await registry.getAgent(agentId);
    expect(agentData.tasksCompleted).to.equal(1);
    expect(agentData.totalEarned).to.equal(amount);
  });

  it("Dispute path: create -> complete -> dispute -> jury resolves for agent", async function () {
    await registry.connect(client).registerAgent(ethers.keccak256(ethers.toUtf8Bytes("client")), client.address);
    await registry.connect(agent).registerAgent(metadataHash, agent.address);

    const agentId = await registry.ownerToId(agent.address);
    const amount = 100n * 10n ** 6n;
    const proofHash = ethers.keccak256(ethers.toUtf8Bytes("task-proof"));

    await usdc.connect(client).approve(await escrow.getAddress(), amount);
    await escrow.connect(client).createTask(agentId, amount, proofHash);
    await escrow.connect(agent).completeTask(1, proofHash);

    // Client disputes
    await escrow.connect(client).disputeTask(1);
    let task = await escrow.getTask(1);
    expect(task.status).to.equal(2); // Disputed

    // Mock jury calls resolveDispute - agent wins
    const agentBalBefore = await usdc.balanceOf(agent.address);
    await escrow.connect(juryAddr).resolveDispute(1, false);

    task = await escrow.getTask(1);
    expect(task.status).to.equal(3); // Resolved
    expect(await usdc.balanceOf(agent.address)).to.equal(agentBalBefore + amount);

    const agentData = await registry.getAgent(agentId);
    expect(agentData.tasksDisputed).to.equal(1);
    expect(agentData.tasksCompleted).to.equal(1);
  });

  it("PaymentIntent: batchPay and claim", async function () {
    await registry.connect(client).registerAgent(ethers.keccak256(ethers.toUtf8Bytes("client")), client.address);
    await registry.connect(agent).registerAgent(metadataHash, agent.address);

    const agentId = await registry.ownerToId(agent.address);
    const amount = 50n * 10n ** 6n;

    await usdc.connect(client).approve(await paymentIntent.getAddress(), amount);
    await paymentIntent.connect(client).pay(agentId, amount, ethers.ZeroHash);

    expect(await paymentIntent.pendingClaims(agentId)).to.equal(amount);

    const balBefore = await usdc.balanceOf(agent.address);
    await paymentIntent.connect(agent).claim();
    expect(await usdc.balanceOf(agent.address)).to.equal(balBefore + amount);
    expect(await paymentIntent.pendingClaims(agentId)).to.equal(0);
  });

  it("Slashing deactivates agent when stake hits 0", async function () {
    await registry.connect(agent).registerAgent(metadataHash, agent.address);
    const agentId = await registry.ownerToId(agent.address);

    // Only escrow can call slash since it owns registry
    await registry.connect(owner).transferOwnership(await escrow.getAddress());
    
    // Impersonate escrow to slash
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [await escrow.getAddress()],
    });
    const escrowSigner = await ethers.getSigner(await escrow.getAddress());
    
    // Fund escrow with ETH for gas
    await owner.sendTransaction({ to: await escrow.getAddress(), value: ethers.parseEther("1") });

    await registry.connect(escrowSigner).slash(agentId, STAKE, "Bad behavior");

    const agentData = await registry.getAgent(agentId);
    expect(agentData.active).to.equal(false);
    expect(agentData.stakeAmount).to.equal(0);
  });
});
