// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AgentRegistry is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct Agent {
        uint256 id;
        bytes32 metadataHash;
        address owner;
        uint256 stakeAmount;
        uint256 tasksCompleted;
        uint256 tasksDisputed;
        uint256 totalEarned;
        bool active;
        uint256 registeredAt;
    }

    struct Stats {
        uint256 totalAgents;
        uint256 activeAgents;
        uint256 totalStakeLocked;
        uint256 totalTasksCompleted;
        uint256 totalTasksDisputed;
        uint256 totalValueSecured;
    }

    IERC20 public immutable USDC;
    uint256 public constant STAKE_AMOUNT = 500e6; // $500 USDC

    uint256 public nextAgentId = 1;
    mapping(uint256 => Agent) public agents;
    mapping(bytes32 => uint256) public metadataToId;
    mapping(address => uint256) public ownerToId;

    uint256 public totalStakeLocked;
    uint256 public totalTasksCompleted;
    uint256 public totalTasksDisputed;
    uint256 public totalValueSecured;

    event AgentRegistered(uint256 indexed id, bytes32 metadataHash, address owner);
    event AgentSlashed(uint256 indexed id, uint256 amount, string reason);
    event StakeRefilled(uint256 indexed id, uint256 amount);
    event TaskRecorded(uint256 indexed id, uint256 value);

    error AlreadyRegistered();
    error InsufficientStake();
    error NotAgentOwner();
    error AgentNotActive();
    error InvalidMetadata();

    constructor(address _usdc) Ownable(msg.sender) {
        USDC = IERC20(_usdc);
    }

    function registerAgent(bytes32 metadataHash, address agentOwner) external nonReentrant returns (uint256) {
        if (metadataHash == bytes32(0)) revert InvalidMetadata();
        if (metadataToId[metadataHash]!= 0) revert AlreadyRegistered();
        if (ownerToId[agentOwner]!= 0) revert AlreadyRegistered();

        USDC.safeTransferFrom(msg.sender, address(this), STAKE_AMOUNT);

        uint256 id = nextAgentId++;
        agents[id] = Agent({
            id: id,
            metadataHash: metadataHash,
            owner: agentOwner,
            stakeAmount: STAKE_AMOUNT,
            tasksCompleted: 0,
            tasksDisputed: 0,
            totalEarned: 0,
            active: true,
            registeredAt: block.timestamp
        });

        metadataToId[metadataHash] = id;
        ownerToId[agentOwner] = id;
        totalStakeLocked += STAKE_AMOUNT;

        emit AgentRegistered(id, metadataHash, agentOwner);
        return id;
    }

    function slash(uint256 agentId, uint256 amount, string calldata reason) external onlyOwner {
        Agent storage agent = agents[agentId];
        require(agent.id!= 0, "Agent not found");
        require(agent.stakeAmount >= amount, "Slash exceeds stake");

        agent.stakeAmount -= amount;
        totalStakeLocked -= amount;

        if (agent.stakeAmount == 0) {
            agent.active = false;
        }

        USDC.safeTransfer(owner(), amount);
        emit AgentSlashed(agentId, amount, reason);
    }

    function refillStake(uint256 amount) external nonReentrant {
        uint256 agentId = ownerToId[msg.sender];
        if (agentId == 0) revert NotAgentOwner();

        Agent storage agent = agents[agentId];
        USDC.safeTransferFrom(msg.sender, address(this), amount);

        agent.stakeAmount += amount;
        totalStakeLocked += amount;

        if (!agent.active && agent.stakeAmount >= STAKE_AMOUNT) {
            agent.active = true;
        }

        emit StakeRefilled(agentId, amount);
    }

    function recordTaskComplete(uint256 agentId, uint256 value) external onlyOwner {
        Agent storage agent = agents[agentId];
        require(agent.id!= 0, "Agent not found");

        agent.tasksCompleted++;
        agent.totalEarned += value;
        totalTasksCompleted++;
        totalValueSecured += value;

        emit TaskRecorded(agentId, value);
    }

    function recordDispute(uint256 agentId) external onlyOwner {
        Agent storage agent = agents[agentId];
        require(agent.id!= 0, "Agent not found");
        agent.tasksDisputed++;
        totalTasksDisputed++;
    }

    function getAgent(uint256 agentId) external view returns (Agent memory) {
        return agents[agentId];
    }

    function getAgentByOwner(address owner) external view returns (Agent memory) {
        return agents[ownerToId[owner]];
    }

    function getStats() external view returns (Stats memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i < nextAgentId; i++) {
            if (agents[i].active) activeCount++;
        }

        return Stats({
            totalAgents: nextAgentId - 1,
            activeAgents: activeCount,
            totalStakeLocked: totalStakeLocked,
            totalTasksCompleted: totalTasksCompleted,
            totalTasksDisputed: totalTasksDisputed,
            totalValueSecured: totalValueSecured
        });
    }
}
