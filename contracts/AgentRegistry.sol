// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract AgentRegistry is Ownable, ReentrancyGuard, Initializable {
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

    address public immutable USDC;
    address public taskEscrow;
    address public verifierOracle;

    uint256 public nextAgentId = 1;
    uint256 public minStake = 500 * 1e6;
    uint256 public constant SCORE_DEFAULT = 500;
    uint256 public constant SLASH_COOLDOWN = 7 days;

    mapping(uint256 => Agent) public agents;
    mapping(address => uint256) public ownerToAgentId;
    mapping(uint256 => uint256) public lastDisputeLost;

    event AgentRegistered(uint256 indexed id, address indexed owner, address wallet, uint256 stake);
    event AgentSlashed(uint256 indexed id, uint256 amount, address indexed slasher, bytes32 evidence);
    event ScoreUpdated(uint256 indexed id, uint16 oldScore, uint16 newScore);
    event StakeWithdrawn(uint256 indexed id, uint256 amount);

    error InsufficientStake();
    error NotAgentOwner();
    error AgentNotActive();
    error StakeLocked();
    error OnlyEscrow();
    error AlreadyRegistered();

    constructor(address _usdc) Ownable(msg.sender) {
        USDC = _usdc;
    }

    function initialize(address _taskEscrow, address _verifier) external initializer onlyOwner {
        taskEscrow = _taskEscrow;
        verifierOracle = _verifier;
    }

    function registerAgent(bytes32 metadataHash, address agentWallet) external nonReentrant returns (uint256) {
        if (ownerToAgentId[msg.sender]!= 0) revert AlreadyRegistered();
        if (agentWallet == address(0)) revert();
        uint256 stakeAmount = _pullUSDC(minStake);
        uint256 agentId = nextAgentId++;
        agents[agentId] = Agent({
            id: agentId,
            owner: msg.sender,
            wallet: agentWallet,
            stake: stakeAmount,
            score: uint16(SCORE_DEFAULT),
            stakeLockedUntil: 0,
            registeredAt: uint64(block.timestamp),
            active: true,
            metadataHash: metadataHash
        });
        ownerToAgentId[msg.sender] = agentId;
        emit AgentRegistered(agentId, msg.sender, agentWallet, stakeAmount);
        return agentId;
    }

    function lockStake(uint256 agentId) external {
        if (msg.sender!= taskEscrow) revert OnlyEscrow();
        agents[agentId].stakeLockedUntil = uint64(block.timestamp + SLASH_COOLDOWN);
    }

    function slash(uint256 agentId, uint256 amount, bytes32 evidenceHash) external {
        if (msg.sender!= taskEscrow) revert OnlyEscrow();
        Agent storage agent = agents[agentId];
        if (!agent.active) revert AgentNotActive();
        uint256 slashAmount = amount > agent.stake? agent.stake : amount;
        agent.stake -= slashAmount;
        agent.score = agent.score > 50? agent.score - 50 : 0;
        lastDisputeLost[agentId] = block.timestamp;
        _transferUSDC(owner(), slashAmount);
        emit AgentSlashed(agentId, slashAmount, msg.sender, evidenceHash);
        if (agent.stake < minStake) {
            agent.active = false;
        }
    }

    function withdrawStake(uint256 amount) external nonReentrant {
        uint256 agentId = ownerToAgentId[msg.sender];
        if (agentId == 0) revert NotAgentOwner();
        Agent storage agent = agents[agentId];
        if (block.timestamp < agent.stakeLockedUntil) revert StakeLocked();
        if (agent.stake - amount < minStake) revert InsufficientStake();
        agent.stake -= amount;
        _transferUSDC(msg.sender, amount);
        emit StakeWithdrawn(agentId, amount);
    }

    function updateScore(uint256 agentId, uint16 newScore) external {
        if (msg.sender!= verifierOracle) revert();
        uint16 oldScore = agents[agentId].score;
        agents[agentId].score = newScore > 1000? 1000 : newScore;
        emit ScoreUpdated(agentId, oldScore, agents[agentId].score);
    }

    function getDisputeMultiplier(uint256 payerId, uint256 workerId) external view returns (uint256) {
        if (lastDisputeLost[workerId] > block.timestamp - 7 days && lastDisputeLost[workerId]!= 0) {
            return 10000;
        }
        return 2000;
    }

    function getAgent(uint256 agentId) external view returns (Agent memory) {
        return agents[agentId];
    }

    function getAgentByOwner(address owner) external view returns (Agent memory) {
        return agents[ownerToAgentId[owner]];
    }

    function _pullUSDC(uint256 amount) internal returns (uint256) {
        (bool success, bytes memory data) = USDC.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDC transfer failed");
        return amount;
    }

    function _transferUSDC(address to, uint256 amount) internal {
        (bool success, bytes memory data) = USDC.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDC transfer failed");
    }
}
