// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AgentRegistry is Ownable {
    address public immutable USDC;

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
        uint32 tasksCompleted;
        uint32 disputesWon;
        uint32 disputesLost;
        uint256 totalEarned;
    }

    struct Stats {
        uint256 totalAgents;
        uint256 activeAgents;
        uint256 totalStakeLocked;
        uint256 totalTasksCompleted;
        uint256 totalDisputes;
        uint256 totalValueSecured;
    }

    uint256 public nextAgentId = 1;
    uint256 public constant MIN_STAKE = 500 * 1e6;
    uint256 public constant SLASH_COOLDOWN = 7 days;
    uint16 public constant BASE_SCORE = 500;

    mapping(uint256 => Agent) public agents;
    mapping(address => uint256) public ownerToAgentId;
    mapping(address => bool) public authorizedContracts;

    uint256 public totalAgentsEver;
    uint256 public totalTasksCompleted;
    uint256 public totalDisputesRaised;
    uint256 public totalDisputesSettled;

    event AgentRegistered(uint256 indexed id, address indexed owner, address indexed wallet, uint256 stake);
    event AgentSlashed(uint256 indexed id, uint256 amount, string reason);
    event ScoreUpdated(uint256 indexed id, uint16 newScore);
    event StakeRefilled(uint256 indexed id, uint256 amount, uint256 newTotal);
    event AgentReactivated(uint256 indexed id);
    event AgentStatsUpdated(uint256 indexed id, uint32 tasksCompleted, uint32 disputesWon, uint32 disputesLost, uint256 totalEarned);

    error AlreadyRegistered();
    error InsufficientStake();
    error NotActive();
    error StakeLocked();
    error NotAgentOwner();
    error NotAuthorized();

    constructor() Ownable(msg.sender) {
        USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    }

    function registerAgent(bytes32 metadataHash, address wallet) external returns (uint256) {
        if (ownerToAgentId[msg.sender]!= 0) revert AlreadyRegistered();

        (bool success, bytes memory data) = USDC.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), MIN_STAKE)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Stake transfer failed");

        uint256 agentId = nextAgentId++;
        agents[agentId] = Agent({
            id: agentId,
            owner: msg.sender,
            wallet: wallet,
            stake: MIN_STAKE,
            score: BASE_SCORE,
            stakeLockedUntil: uint64(block.timestamp + SLASH_COOLDOWN),
            registeredAt: uint64(block.timestamp),
            active: true,
            metadataHash: metadataHash,
            tasksCompleted: 0,
            disputesWon: 0,
            disputesLost: 0,
            totalEarned: 0
        });
        ownerToAgentId[msg.sender] = agentId;
        totalAgentsEver++;

        emit AgentRegistered(agentId, msg.sender, wallet, MIN_STAKE);
        return agentId;
    }

    function refillStake(uint256 amount) external {
        uint256 agentId = ownerToAgentId[msg.sender];
        if (agentId == 0) revert NotAgentOwner();
        Agent storage agent = agents[agentId];

        (bool success, bytes memory data) = USDC.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Stake transfer failed");

        bool wasInactive =!agent.active;
        agent.stake += amount;
        agent.stakeLockedUntil = uint64(block.timestamp + SLASH_COOLDOWN);

        if (agent.stake >= MIN_STAKE && wasInactive) {
            agent.active = true;
            emit AgentReactivated(agentId);
        }

        emit StakeRefilled(agentId, amount, agent.stake);
    }

    function slash(uint256 agentId, uint256 amount, string calldata reason) external onlyOwner {
        Agent storage agent = agents[agentId];
        if (!agent.active) revert NotActive();
        if (block.timestamp < agent.stakeLockedUntil) revert StakeLocked();
        if (amount > agent.stake) amount = agent.stake;

        agent.stake -= amount;
        agent.score = agent.score > 50? agent.score - 50 : 0;

        if (agent.stake < MIN_STAKE) {
            agent.active = false;
        }

        (bool success,) = USDC.call(abi.encodeWithSignature("transfer(address,uint256)", owner(), amount));
        require(success, "Slash transfer failed");

        emit AgentSlashed(agentId, amount, reason);
        emit ScoreUpdated(agentId, agent.score);
    }

    function updateScore(uint256 agentId, int16 delta) external onlyOwner {
        Agent storage agent = agents[agentId];
        if (!agent.active) revert NotActive();

        if (delta >= 0) {
            agent.score = agent.score + uint16(delta) > 1000? 1000 : agent.score + uint16(delta);
        } else {
            uint16 absDelta = uint16(-delta);
            agent.score = agent.score > absDelta? agent.score - absDelta : 0;
        }
        emit ScoreUpdated(agentId, agent.score);
    }

    function recordTaskComplete(uint256 agentId, uint256 earned) external {
        if (!isAuthorizedContract(msg.sender) && msg.sender!= owner()) revert NotAuthorized();
        Agent storage agent = agents[agentId];
        agent.tasksCompleted++;
        agent.totalEarned += earned;
        totalTasksCompleted++;
        emit AgentStatsUpdated(agentId, agent.tasksCompleted, agent.disputesWon, agent.disputesLost, agent.totalEarned);
    }

    function recordDisputeResult(uint256 agentId, bool won) external {
        if (!isAuthorizedContract(msg.sender) && msg.sender!= owner()) revert NotAuthorized();
        Agent storage agent = agents[agentId];
        if (won) agent.disputesWon++;
        else agent.disputesLost++;
        totalDisputesRaised++;
        totalDisputesSettled++;
        emit AgentStatsUpdated(agentId, agent.tasksCompleted, agent.disputesWon, agent.disputesLost, agent.totalEarned);
    }

    function setAuthorizedContract(address contractAddr, bool authorized) external onlyOwner {
        authorizedContracts[contractAddr] = authorized;
    }

    function isAuthorizedContract(address contractAddr) public view returns (bool) {
        return authorizedContracts[contractAddr];
    }

    function getStats() external view returns (Stats memory) {
        uint256 activeCount = 0;
        uint256 totalStake = 0;

        for (uint256 i = 1; i < nextAgentId; i++) {
            if (agents[i].active) activeCount++;
            totalStake += agents[i].stake;
        }

        return Stats({
            totalAgents: totalAgentsEver,
            activeAgents: activeCount,
            totalStakeLocked: totalStake,
            totalTasksCompleted: totalTasksCompleted,
            totalDisputes: totalDisputesRaised,
            totalValueSecured: totalStake
        });
    }

    function getAgent(uint256 agentId) external view returns (Agent memory) {
        return agents[agentId];
    }

    function getAgentByOwner(address owner) external view returns (Agent memory) {
        return agents[ownerToAgentId[owner]];
    }
}
