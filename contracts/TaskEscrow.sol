// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAgentRegistry {
    struct Agent {
        uint256 id;
        address owner;
        address wallet;
        uint256 stake;
        uint16 score;
        uint64 stakeLockedUntil;
        uint64 registeredAt;
        bool active;
        bytes32 metadataHash;
    }
    function getAgent(uint256 agentId) external view returns (Agent memory);
    function lockStake(uint256 agentId) external;
    function slash(uint256 agentId, uint256 amount, bytes32 evidenceHash) external;
    function getDisputeMultiplier(uint256 payerId, uint256 workerId) external view returns (uint256);
    function updateScore(uint256 agentId, uint16 newScore) external;
}

interface ILLMJuryVerifier {
    function requestVerdict(uint256 taskId) external;
}

contract TaskEscrow is ReentrancyGuard, Ownable {
    enum Status { None, Created, Submitted, Disputed, Resolved, Cancelled }

    struct Task {
        uint256 id;
        uint256 fromAgentId;
        uint256 toAgentId;
        uint256 amount;
        bytes32 specHash;
        bytes32 resultHash;
        bytes32 defenseHash;
        address verifier;
        Status status;
        uint64 createdAt;
        uint64 deadline;
        uint64 disputeDeadline;
        uint256 disputeFee;
        bytes disputeReason;
    }

    address public immutable USDC;
    IAgentRegistry public immutable REGISTRY;

    uint256 public nextTaskId = 1;
    uint256 public protocolFeeBps = 100;
    uint256 public constant DISPUTE_WINDOW = 24 hours;
    uint256 public constant DEFAULT_DISPUTE_BPS = 2000;
    uint256 public constant WINNER_BONUS_BPS = 500;

    mapping(uint256 => Task) public tasks;
    mapping(uint256 => mapping(uint256 => uint256)) public lastDisputeBetween;

    event TaskCreated(uint256 indexed id, uint256 indexed from, uint256 indexed to, uint256 amount, address verifier);
    event ProofSubmitted(uint256 indexed id, bytes32 resultHash, uint64 disputeDeadline);
    event Disputed(uint256 indexed id, address disputer, uint256 fee, bytes reason);
    event DefenseSubmitted(uint256 indexed id, bytes32 defenseHash);
    event Resolved(uint256 indexed id, bool payerWon, uint256 slashAmount);
    event Cancelled(uint256 indexed id);

    error NotTaskParty();
    error InvalidStatus();
    error DeadlinePassed();
    error DisputeWindowOver();
    error AlreadyDisputed();
    error InsufficientDisputeFee();
    error OnlyVerifier();

    constructor(address _usdc, address _registry) Ownable(msg.sender) {
        USDC = _usdc;
        REGISTRY = IAgentRegistry(_registry);
    }

    function createTask(uint256 toAgentId, uint256 amount, bytes32 specHash, address verifier, uint64 deadline) external nonReentrant returns (uint256) {
        IAgentRegistry.Agent memory payer = REGISTRY.getAgentByOwner(msg.sender);
        IAgentRegistry.Agent memory worker = REGISTRY.getAgent(toAgentId);
        require(payer.id!= 0 && payer.active, "Payer not registered");
        require(worker.id!= 0 && worker.active, "Worker not registered");
        require(deadline > block.timestamp, "Deadline in past");
        require(amount > 0, "Amount 0");
        uint256 fee = amount * protocolFeeBps / 10000;
        uint256 total = amount + fee;
        _pullUSDC(total);
        uint256 taskId = nextTaskId++;
        tasks[taskId] = Task({
            id: taskId,
            fromAgentId: payer.id,
            toAgentId: toAgentId,
            amount: amount,
            specHash: specHash,
            resultHash: bytes32(0),
            defenseHash: bytes32(0),
            verifier: verifier,
            status: Status.Created,
            createdAt: uint64(block.timestamp),
            deadline: deadline,
            disputeDeadline: 0,
            disputeFee: 0,
            disputeReason: ""
        });
        emit TaskCreated(taskId, payer.id, toAgentId, amount, verifier);
        return taskId;
    }

    function submitProof(uint256 taskId, bytes32 resultHash) external nonReentrant {
        Task storage task = tasks[taskId];
        IAgentRegistry.Agent memory worker = REGISTRY.getAgent(task.toAgentId);
        require(msg.sender == worker.owner, "Not worker");
        require(task.status == Status.Created, "Invalid status");
        require(block.timestamp <= task.deadline, "Deadline passed");
        task.resultHash = resultHash;
        task.status = Status.Submitted;
        task.disputeDeadline = uint64(block.timestamp + DISPUTE_WINDOW);
        REGISTRY.lockStake(task.toAgentId);
        emit ProofSubmitted(taskId, resultHash, task.disputeDeadline);
    }

    function dispute(uint256 taskId, bytes calldata reason) external payable nonReentrant {
        Task storage task = tasks[taskId];
        IAgentRegistry.Agent memory payer = REGISTRY.getAgent(task.fromAgentId);
        require(msg.sender == payer.owner, "Not payer");
        require(task.status == Status.Submitted, "Not submitted");
        require(block.timestamp <= task.disputeDeadline, "Dispute window over");
        uint256 disputeBps = REGISTRY.getDisputeMultiplier(task.fromAgentId, task.toAgentId);
        uint256 requiredFee = task.amount * disputeBps / 10000;
        require(msg.value >= requiredFee, "Insufficient dispute fee");
        task.status = Status.Disputed;
        task.disputeFee = msg.value;
        task.disputeReason = reason;
        lastDisputeBetween[task.fromAgentId][task.toAgentId] = block.timestamp;
        emit Disputed(taskId, msg.sender, msg.value, reason);
        ILLMJuryVerifier(task.verifier).requestVerdict(taskId);
    }

    function submitDefense(uint256 taskId, bytes calldata evidence) external nonReentrant {
        Task storage task = tasks[taskId];
        IAgentRegistry.Agent memory worker = REGISTRY.getAgent(task.toAgentId);
        require(msg.sender == worker.owner, "Not worker");
        require(task.status == Status.Disputed, "Not disputed");
        require(block.timestamp <= task.disputeDeadline, "Defense window over");
        require(task.defenseHash == bytes32(0), "Defense already submitted");
        task.defenseHash = keccak256(evidence);
        emit DefenseSubmitted(taskId, task.defenseHash);
    }

    function resolve(uint256 taskId, bool payerWon) external nonReentrant {
        Task storage task = tasks[taskId];
        require(msg.sender == task.verifier, "Only verifier");
        require(task.status == Status.Disputed, "Not disputed");
        task.status = Status.Resolved;
        uint256 slashAmount = 0;
        address winner;
        if (payerWon) {
            IAgentRegistry.Agent memory worker = REGISTRY.getAgent(task.toAgentId);
            slashAmount = worker.stake * 1000 / 10000;
            bytes32 evidence = keccak256(abi.encodePacked(task.specHash, task.resultHash, task.defenseHash));
            REGISTRY.slash(task.toAgentId, slashAmount, evidence);
            _transferUSDC(REGISTRY.getAgent(task.fromAgentId).owner, task.amount);
            winner = REGISTRY.getAgent(task.fromAgentId).owner;
            REGISTRY.updateScore(task.fromAgentId, REGISTRY.getAgent(task.fromAgentId).score + 5);
        } else {
            _transferUSDC(REGISTRY.getAgent(task.toAgentId).owner, task.amount);
            winner = REGISTRY.getAgent(task.toAgentId).owner;
            REGISTRY.updateScore(task.toAgentId, REGISTRY.getAgent(task.toAgentId).score + 5);
            IAgentRegistry.Agent memory payer = REGISTRY.getAgent(task.fromAgentId);
            uint16 newScore = payer.score > 10? payer.score - 10 : 0;
            REGISTRY.updateScore(task.fromAgentId, newScore);
        }
        uint256 winnerCut = task.disputeFee * 9500 / 10000;
        (bool sent, ) = winner.call{value: winnerCut}("");
        require(sent, "ETH send failed");
        emit Resolved(taskId, payerWon, slashAmount);
    }

    function release(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        require(task.status == Status.Submitted, "Not submitted");
        require(block.timestamp > task.disputeDeadline, "Still in dispute window");
        task.status = Status.Resolved;
        _transferUSDC(REGISTRY.getAgent(task.toAgentId).owner, task.amount);
        uint16 newScore = REGISTRY.getAgent(task.toAgentId).score + 5;
        REGISTRY.updateScore(task.toAgentId, newScore > 1000? 1000 : newScore);
    }

    function cancelExpired(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        require(task.status == Status.Created, "Not pending");
        require(block.timestamp > task.deadline, "Deadline not passed");
        task.status = Status.Cancelled;
        uint256 refund = task.amount + (task.amount * protocolFeeBps / 10000);
        _transferUSDC(REGISTRY.getAgent(task.fromAgentId).owner, refund);
        IAgentRegistry.Agent memory worker = REGISTRY.getAgent(task.toAgentId);
        uint256 abandonPenalty = worker.stake * 500 / 10000;
        REGISTRY.slash(task.toAgentId, abandonPenalty, keccak256("ABANDONED_TASK"));
        uint16 newScore = worker.score > 25? worker.score - 25 : 0;
        REGISTRY.updateScore(task.toAgentId, newScore);
        emit Cancelled(taskId);
    }

    function cancel(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        require(msg.sender == REGISTRY.getAgent(task.fromAgentId).owner, "Not payer");
        require(task.status == Status.Created, "Already started");
        task.status = Status.Cancelled;
        uint256 refund = task.amount + (task.amount * protocolFeeBps / 10000);
        _transferUSDC(msg.sender, refund);
        emit Cancelled(taskId);
    }

    function getTask(uint256 taskId) external view returns (Task memory) {
        return tasks[taskId];
    }

    function _pullUSDC(uint256 amount) internal {
        (bool success, bytes memory data) = USDC.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDC pull failed");
    }

    function _transferUSDC(address to, uint256 amount) internal {
        (bool success, bytes memory data) = USDC.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDC send failed");
    }

    receive() external payable {}
}
