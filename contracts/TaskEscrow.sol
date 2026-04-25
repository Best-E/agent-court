// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AgentRegistry.sol";

interface IVerifier {
    function verify(bytes calldata data) external returns (bool);
}

contract TaskEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    AgentRegistry public immutable REGISTRY;
    IERC20 public immutable USDC;

    enum Status { Created, Submitted, Disputed, Resolved, Cancelled }

    struct Task {
        uint256 id;
        uint256 fromAgentId;
        uint256 toAgentId;
        uint256 amount;
        bytes32 specHash;
        bytes32 resultHash;
        bytes32 defenseHash;
        address verifier;
        uint64 deadline;
        uint64 disputeDeadline;
        Status status;
        bool payerWon;
    }

    uint256 public nextTaskId = 1;
    uint256 public constant PROTOCOL_FEE_BPS = 100;
    uint256 public constant DISPUTE_WINDOW = 24 hours;

    mapping(uint256 => Task) public tasks;
    mapping(uint256 => uint256) public disputeBonds;

    event TaskCreated(uint256 indexed id, uint256 indexed from, uint256 indexed to, uint256 amount);
    event TaskSubmitted(uint256 indexed id, bytes32 resultHash);
    event TaskDisputed(uint256 indexed id, string reason);
    event TaskResolved(uint256 indexed id, bool payerWon);

    error NotPayer();
    error NotWorker();
    error InvalidStatus();
    error DeadlinePassed();
    error DisputeWindowClosed();

    constructor(address _registry) {
        REGISTRY = AgentRegistry(_registry);
        USDC = IERC20(REGISTRY.USDC());
        REGISTRY.setAuthorizedContract(address(this), true);
    }

    function createTask(
        uint256 toAgentId,
        uint256 amount,
        bytes32 specHash,
        address verifier,
        uint64 deadline
    ) external nonReentrant returns (uint256) {
        AgentRegistry.Agent memory from = REGISTRY.getAgentByOwner(msg.sender);
        AgentRegistry.Agent memory to = REGISTRY.getAgent(toAgentId);
        require(from.id!= 0 && from.active, "Invalid payer");
        require(to.id!= 0 && to.active, "Invalid worker");
        require(deadline > block.timestamp, "Deadline passed");

        uint256 fee = (amount * PROTOCOL_FEE_BPS) / 10000;
        USDC.safeTransferFrom(msg.sender, address(this), amount + fee);

        uint256 taskId = nextTaskId++;
        tasks[taskId] = Task({
            id: taskId,
            fromAgentId: from.id,
            toAgentId: toAgentId,
            amount: amount,
            specHash: specHash,
            resultHash: 0,
            defenseHash: 0,
            verifier: verifier,
            deadline: deadline,
            disputeDeadline: 0,
            status: Status.Created,
            payerWon: false
        });

        emit TaskCreated(taskId, from.id, toAgentId, amount);
        return taskId;
    }

    function submitProof(uint256 taskId, bytes32 resultHash) external nonReentrant {
        Task storage task = tasks[taskId];
        AgentRegistry.Agent memory worker = REGISTRY.getAgentByOwner(msg.sender);
        if (worker.id!= task.toAgentId) revert NotWorker();
        if (task.status!= Status.Created) revert InvalidStatus();
        if (block.timestamp > task.deadline) revert DeadlinePassed();

        task.resultHash = resultHash;
        task.status = Status.Submitted;
        task.disputeDeadline = uint64(block.timestamp + DISPUTE_WINDOW);

        emit TaskSubmitted(taskId, resultHash);
    }

    function dispute(uint256 taskId, string calldata reason) external payable nonReentrant {
        Task storage task = tasks[taskId];
        AgentRegistry.Agent memory payer = REGISTRY.getAgentByOwner(msg.sender);
        if (payer.id!= task.fromAgentId) revert NotPayer();
        if (task.status!= Status.Submitted) revert InvalidStatus();
        if (block.timestamp > task.disputeDeadline) revert DisputeWindowClosed();

        uint256 bond = (task.amount * getDisputeMultiplier(task.toAgentId)) / 10000;
        require(msg.value >= bond, "Insufficient bond");

        task.status = Status.Disputed;
        disputeBonds[taskId] = msg.value;

        emit TaskDisputed(taskId, reason);
    }

    function submitDefense(uint256 taskId, bytes32 defenseHash) external nonReentrant {
        Task storage task = tasks[taskId];
        AgentRegistry.Agent memory worker = REGISTRY.getAgentByOwner(msg.sender);
        if (worker.id!= task.toAgentId) revert NotWorker();
        if (task.status!= Status.Disputed) revert InvalidStatus();

        task.defenseHash = defenseHash;
    }

    function resolve(uint256 taskId, bool payerWon) external nonReentrant {
        Task storage task = tasks[taskId];
        require(msg.sender == task.verifier, "Not verifier");
        require(task.status == Status.Disputed, "Not disputed");

        task.status = Status.Resolved;
        task.payerWon = payerWon;

        AgentRegistry.Agent memory worker = REGISTRY.getAgent(task.toAgentId);
        AgentRegistry.Agent memory payer = REGISTRY.getAgent(task.fromAgentId);

        if (payerWon) {
            USDC.safeTransfer(payer.wallet, task.amount);
            REGISTRY.slash(task.toAgentId, task.amount / 10, "Lost dispute");
            REGISTRY.updateScore(task.toAgentId, -50);
            REGISTRY.updateScore(task.fromAgentId, 5);
            REGISTRY.recordDisputeResult(task.toAgentId, false);
            REGISTRY.recordDisputeResult(task.fromAgentId, true);
            payable(payer.owner).transfer(disputeBonds[taskId]);
        } else {
            USDC.safeTransfer(worker.wallet, task.amount);
            REGISTRY.updateScore(task.toAgentId, 5);
            REGISTRY.updateScore(task.fromAgentId, -10);
            REGISTRY.recordDisputeResult(task.toAgentId, true);
            REGISTRY.recordDisputeResult(task.fromAgentId, false);
            REGISTRY.recordTaskComplete(task.toAgentId, task.amount);
            payable(worker.owner).transfer(disputeBonds[taskId]);
        }

        emit TaskResolved(taskId, payerWon);
    }

    function cancelExpired(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        require(task.status == Status.Created, "Not created");
        require(block.timestamp > task.deadline, "Not expired");

        task.status = Status.Cancelled;
        AgentRegistry.Agent memory payer = REGISTRY.getAgent(task.fromAgentId);
        USDC.safeTransfer(payer.wallet, task.amount);

        REGISTRY.slash(task.toAgentId, task.amount / 20, "Abandoned task");
        REGISTRY.updateScore(task.toAgentId, -25);
    }

    function getDisputeMultiplier(uint256 agentId) public view returns (uint256) {
        AgentRegistry.Agent memory agent = REGISTRY.getAgent(agentId);
        if (agent.score >= 800) return 2000;
        if (agent.score >= 600) return 5000;
        return 10000;
    }
}
