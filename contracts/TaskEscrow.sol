// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AgentRegistry.sol";
import "./interfaces/ILLMJuryVerifier.sol";

contract TaskEscrow is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    enum TaskStatus { Created, Completed, Disputed, Resolved, Cancelled }

    struct Task {
        uint256 id;
        uint256 clientId;
        uint256 agentId;
        uint256 amount;
        bytes32 proofHash;
        TaskStatus status;
        uint256 createdAt;
        uint256 completedAt;
        bool clientApproved;
        bool agentApproved;
    }

    AgentRegistry public immutable registry;
    IERC20 public immutable USDC;
    ILLMJuryVerifier public juryVerifier;

    uint256 public nextTaskId = 1;
    mapping(uint256 => Task) public tasks;
    mapping(uint256 => uint256) public escrowedAmounts;

    event TaskCreated(uint256 indexed id, uint256 indexed clientId, uint256 indexed agentId, uint256 amount);
    event TaskCompleted(uint256 indexed id, bytes32 proofHash);
    event TaskDisputed(uint256 indexed id);
    event TaskResolved(uint256 indexed id, bool clientWon);
    event TaskCancelled(uint256 indexed id);
    event JuryVerifierSet(address verifier);

    error TaskNotFound();
    error NotClient();
    error NotAgent();
    error InvalidStatus();
    error AlreadyApproved();

    constructor(address _registry) Ownable(msg.sender) {
        registry = AgentRegistry(_registry);
        USDC = registry.USDC();
    }

    function setJuryVerifier(address _verifier) external onlyOwner {
        juryVerifier = ILLMJuryVerifier(_verifier);
        emit JuryVerifierSet(_verifier);
    }

    function createTask(uint256 agentId, uint256 amount, bytes32 proofHash) external nonReentrant returns (uint256) {
        uint256 clientId = registry.getAgentByOwner(msg.sender).id;
        require(clientId!= 0, "Client not registered");
        require(registry.getAgent(agentId).active, "Agent not active");
        require(amount > 0, "Amount 0");

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        uint256 id = nextTaskId++;
        tasks[id] = Task({
            id: id,
            clientId: clientId,
            agentId: agentId,
            amount: amount,
            proofHash: proofHash,
            status: TaskStatus.Created,
            createdAt: block.timestamp,
            completedAt: 0,
            clientApproved: false,
            agentApproved: false
        });

        escrowedAmounts[id] = amount;
        emit TaskCreated(id, clientId, agentId, amount);
        return id;
    }

    function completeTask(uint256 taskId, bytes32 proofHash) external nonReentrant {
        Task storage task = tasks[taskId];
        if (task.id == 0) revert TaskNotFound();
        if (registry.getAgentByOwner(msg.sender).id!= task.agentId) revert NotAgent();
        if (task.status!= TaskStatus.Created) revert InvalidStatus();

        task.status = TaskStatus.Completed;
        task.completedAt = block.timestamp;
        task.proofHash = proofHash;
        task.agentApproved = true;

        emit TaskCompleted(taskId, proofHash);
    }

    function approveTask(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        if (task.id == 0) revert TaskNotFound();
        if (registry.getAgentByOwner(msg.sender).id!= task.clientId) revert NotClient();
        if (task.status!= TaskStatus.Completed) revert InvalidStatus();
        if (task.clientApproved) revert AlreadyApproved();

        task.clientApproved = true;

        _payout(taskId, task.agentId);
        registry.recordTaskComplete(task.agentId, task.amount);

        task.status = TaskStatus.Resolved;
        emit TaskResolved(taskId, false);
    }

    function disputeTask(uint256 taskId) external {
        Task storage task = tasks[taskId];
        if (task.id == 0) revert TaskNotFound();
        if (registry.getAgentByOwner(msg.sender).id!= task.clientId) revert NotClient();
        if (task.status!= TaskStatus.Completed) revert InvalidStatus();

        task.status = TaskStatus.Disputed;
        registry.recordDispute(task.agentId);

        if (address(juryVerifier)!= address(0)) {
            juryVerifier.requestVerification(taskId);
        }

        emit TaskDisputed(taskId);
    }

    function resolveDispute(uint256 taskId, bool clientWon) external {
        require(msg.sender == address(juryVerifier), "Only jury");
        Task storage task = tasks[taskId];
        if (task.id == 0) revert TaskNotFound();
        if (task.status!= TaskStatus.Disputed) revert InvalidStatus();

        task.status = TaskStatus.Resolved;

        if (clientWon) {
            _payout(taskId, task.clientId);
        } else {
            _payout(taskId, task.agentId);
            registry.recordTaskComplete(task.agentId, task.amount);
        }

        emit TaskResolved(taskId, clientWon);
    }

    function cancelTask(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        if (task.id == 0) revert TaskNotFound();
        if (registry.getAgentByOwner(msg.sender).id!= task.clientId) revert NotClient();
        if (task.status!= TaskStatus.Created) revert InvalidStatus();

        task.status = TaskStatus.Cancelled;
        _payout(taskId, task.clientId);

        emit TaskCancelled(taskId);
    }

    function _payout(uint256 taskId, uint256 recipientId) internal {
        uint256 amount = escrowedAmounts[taskId];
        require(amount > 0, "Nothing to pay");

        escrowedAmounts[taskId] = 0;
        address recipient = registry.getAgent(recipientId).owner;
        USDC.safeTransfer(recipient, amount);
    }

    function getTask(uint256 taskId) external view returns (Task memory) {
        return tasks[taskId];
    }
}
