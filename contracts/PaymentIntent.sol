// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AgentRegistry.sol";

contract PaymentIntent is ReentrancyGuard {
    using SafeERC20 for IERC20;

    AgentRegistry public immutable registry;
    IERC20 public immutable USDC;

    mapping(uint256 => uint256) public pendingClaims;

    event PaymentMade(uint256 indexed payerId, uint256 indexed payeeId, uint256 amount, bytes32 proofHash);
    event BatchPaymentMade(uint256 indexed payerId, uint256 count, bytes32 proofHash);
    event ClaimsWithdrawn(uint256 indexed agentId, uint256 amount);
    event DustSwept(uint256 indexed agentId, uint256 amount);

    error DuplicateRecipient();
    error InvalidAmount();
    error AgentNotFound();
    error NoClaims();

    constructor(address _registry) {
        registry = AgentRegistry(_registry);
        USDC = registry.USDC();
    }

    function pay(uint256 payeeId, uint256 amount, bytes32 proofHash) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (registry.getAgent(payeeId).id == 0) revert AgentNotFound();

        uint256 payerId = registry.getAgentByOwner(msg.sender).id;
        require(payerId!= 0, "Payer not registered");

        USDC.safeTransferFrom(msg.sender, address(this), amount);
        pendingClaims[payeeId] += amount;

        emit PaymentMade(payerId, payeeId, amount, proofHash);
    }

    function batchPay(uint256[] calldata payeeIds, uint256[] calldata amounts, bytes32 proofHash) external nonReentrant {
        require(payeeIds.length == amounts.length, "Length mismatch");
        require(payeeIds.length > 0, "Empty batch");

        uint256 payerId = registry.getAgentByOwner(msg.sender).id;
        require(payerId!= 0, "Payer not registered");

        uint256 total = 0;
        for (uint256 i = 0; i < payeeIds.length; i++) {
            for (uint256 j = i + 1; j < payeeIds.length; j++) {
                if (payeeIds[i] == payeeIds[j]) revert DuplicateRecipient();
            }
            if (registry.getAgent(payeeIds[i]).id == 0) revert AgentNotFound();
            if (amounts[i] == 0) revert InvalidAmount();

            pendingClaims[payeeIds[i]] += amounts[i];
            total += amounts[i];
        }

        USDC.safeTransferFrom(msg.sender, address(this), total);
        emit BatchPaymentMade(payerId, payeeIds.length, proofHash);
    }

    function claim() external nonReentrant {
        uint256 agentId = registry.getAgentByOwner(msg.sender).id;
        if (agentId == 0) revert AgentNotFound();

        uint256 amount = pendingClaims[agentId];
        if (amount == 0) revert NoClaims();

        pendingClaims[agentId] = 0;
        USDC.safeTransfer(msg.sender, amount);

        emit ClaimsWithdrawn(agentId, amount);
    }

    function sweepDust() external nonReentrant {
        uint256 agentId = registry.getAgentByOwner(msg.sender).id;
        if (agentId == 0) revert AgentNotFound();

        uint256 amount = pendingClaims[agentId];
        require(amount > 0 && amount < 10000, "Not dust"); // <$0.01

        pendingClaims[agentId] = 0;
        USDC.safeTransfer(msg.sender, amount);

        emit DustSwept(agentId, amount);
    }
}
