// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        uint32 tasksCompleted;
        uint32 disputesWon;
        uint32 disputesLost;
        uint256 totalEarned;
    }
    function getAgent(uint256 agentId) external view returns (Agent memory);
    function getAgentByOwner(address owner) external view returns (Agent memory);
    function USDC() external view returns (address);
    function setAuthorizedContract(address contractAddr, bool authorized) external;
    function recordTaskComplete(uint256 agentId, uint256 earned) external;
}

contract PaymentIntent is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    IAgentRegistry public immutable REGISTRY;
    IERC20 public immutable USDC;

    struct Payment {
        uint256 fromAgentId;
        uint256 toAgentId;
        uint256 amount;
        bytes32 memoHash;
        uint64 timestamp;
        bool claimed;
    }

    uint256 public nextPaymentId = 1;
    uint256 public constant MAX_BATCH_SIZE = 100;
    uint256 public constant MIN_PAYMENT = 1;
    uint256 public constant MAX_PAYMENTS_PER_BLOCK = 100;
    uint256 public constant DUST_THRESHOLD = 10000;

    mapping(uint256 => Payment) public payments;
    mapping(uint256 => uint256) public pendingClaims;
    mapping(address => uint256) public lastPaymentBlock;
    mapping(address => uint256) public paymentsInBlock;

    event PaymentCreated(uint256 indexed id, uint256 indexed from, uint256 indexed to, uint256 amount, bytes32 memoHash);
    event BatchPaymentCreated(uint256 indexed from, uint256 totalAmount, uint256 recipientCount, bytes32 batchMemoHash, uint256 firstPaymentId, uint256 lastPaymentId);
    event PaymentClaimed(uint256 indexed paymentId, uint256 indexed toAgentId, address indexed recipient, uint256 amount);
    event BatchClaimed(uint256 indexed toAgentId, address indexed recipient, uint256 amount);
    event DustSwept(uint256 indexed toAgentId, address indexed recipient, uint256 amount);
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed to);

    error NotRegisteredSender();
    error NotRegisteredRecipient();
    error InvalidAgentId();
    error InvalidAgentWallet();
    error BatchTooLarge();
    error AmountTooSmall();
    error RateLimitExceeded();
    error AlreadyClaimed();
    error NotPaymentRecipient();
    error NothingToClaim();
    error ArrayLengthMismatch();
    error DuplicateRecipient();
    error ZeroAddress();
    error DustTooLarge();

    constructor(address _registry) Ownable(msg.sender) {
        if (_registry == address(0)) revert ZeroAddress();
        REGISTRY = IAgentRegistry(_registry);
        USDC = IERC20(REGISTRY.USDC());
        if (address(USDC) == address(0)) revert ZeroAddress();
        REGISTRY.setAuthorizedContract(address(this), true);
    }

    function pay(uint256 toAgentId, uint256 amount, bytes32 memoHash) external nonReentrant whenNotPaused returns (uint256) {
        _rateLimitCheck();
        IAgentRegistry.Agent memory from = REGISTRY.getAgentByOwner(msg.sender);
        if (from.id == 0 ||!from.active) revert NotRegisteredSender();
        IAgentRegistry.Agent memory to = REGISTRY.getAgent(toAgentId);
        if (to.id == 0) revert InvalidAgentId();
        if (!to.active) revert NotRegisteredRecipient();
        if (to.wallet == address(0)) revert InvalidAgentWallet();
        if (amount < MIN_PAYMENT) revert AmountTooSmall();

        uint256 paymentId = nextPaymentId++;
        payments[paymentId] = Payment({
            fromAgentId: from.id,
            toAgentId: toAgentId,
            amount: amount,
            memoHash: memoHash,
            timestamp: uint64(block.timestamp),
            claimed: false
        });
        pendingClaims[toAgentId] += amount;
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        emit PaymentCreated(paymentId, from.id, toAgentId, amount, memoHash);
        return paymentId;
    }

    function batchPay(uint256[] calldata toAgentIds, uint256[] calldata amounts, bytes32 batchMemoHash) external nonReentrant whenNotPaused returns (uint256[] memory) {
        _rateLimitCheck();
        uint256 len = toAgentIds.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (len!= amounts.length) revert ArrayLengthMismatch();

        IAgentRegistry.Agent memory from = REGISTRY.getAgentByOwner(msg.sender);
        if (from.id == 0 ||!from.active) revert NotRegisteredSender();

        uint256 totalAmount = 0;
        uint256[] memory paymentIds = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            if (amounts[i] < MIN_PAYMENT) revert AmountTooSmall();
            IAgentRegistry.Agent memory to = REGISTRY.getAgent(toAgentIds[i]);
            if (to.id == 0) revert InvalidAgentId();
            if (!to.active) revert NotRegisteredRecipient();
            if (to.wallet == address(0)) revert InvalidAgentWallet();
            for (uint256 j = 0; j < i; j++) {
                if (toAgentIds[i] == toAgentIds[j]) revert DuplicateRecipient();
            }
            totalAmount += amounts[i];
        }

        USDC.safeTransferFrom(msg.sender, address(this), totalAmount);

        uint256 firstId = nextPaymentId;
        for (uint256 i = 0; i < len; i++) {
            uint256 paymentId = nextPaymentId++;
            payments[paymentId] = Payment({
                fromAgentId: from.id,
                toAgentId: toAgentIds[i],
                amount: amounts[i],
                memoHash: batchMemoHash,
                timestamp: uint64(block.timestamp),
                claimed: false
            });
            pendingClaims[toAgentIds[i]] += amounts[i];
            paymentIds[i] = paymentId;
        }

        emit BatchPaymentCreated(from.id, totalAmount, len, batchMemoHash, firstId, nextPaymentId - 1);
        return paymentIds;
    }

    function claimPayment(uint256 paymentId) external nonReentrant {
        Payment storage p = payments[paymentId];
        if (p.claimed) revert AlreadyClaimed();
        if (p.amount == 0) revert InvalidAgentId();
        IAgentRegistry.Agent memory recipient = REGISTRY.getAgent(p.toAgentId);
        if (msg.sender!= recipient.owner) revert NotPaymentRecipient();
        p.claimed = true;
        pendingClaims[p.toAgentId] -= p.amount;
        USDC.safeTransfer(recipient.wallet, p.amount);
        REGISTRY.recordTaskComplete(p.toAgentId, p.amount);
        emit PaymentClaimed(paymentId, p.toAgentId, recipient.wallet, p.amount);
    }

    function claimAll() external nonReentrant {
        IAgentRegistry.Agent memory recipient = REGISTRY.getAgentByOwner(msg.sender);
        uint256 amount = pendingClaims[recipient.id];
        if (amount == 0) revert NothingToClaim();
        if (recipient.wallet == address(0)) revert InvalidAgentWallet();
        pendingClaims[recipient.id] = 0;
        USDC.safeTransfer(recipient.wallet, amount);
        REGISTRY.recordTaskComplete(recipient.id, amount);
        emit BatchClaimed(recipient.id, recipient.wallet, amount);
    }

    function sweepDust() external nonReentrant {
        IAgentRegistry.Agent memory recipient = REGISTRY.getAgentByOwner(msg.sender);
        uint256 amount = pendingClaims[recipient.id];
        if (amount == 0) revert NothingToClaim();
        if (amount > DUST_THRESHOLD) revert DustTooLarge();
        if (recipient.wallet == address(0)) revert InvalidAgentWallet();
        pendingClaims[recipient.id] = 0;
        USDC.safeTransfer(recipient.wallet, amount);
        REGISTRY.recordTaskComplete(recipient.id, amount);
        emit DustSwept(recipient.id, recipient.wallet, amount);
    }

    function _rateLimitCheck() internal {
        if (lastPaymentBlock[msg.sender] < block.number) {
            lastPaymentBlock[msg.sender] = block.number;
            paymentsInBlock[msg.sender] = 1;
        } else {
            paymentsInBlock[msg.sender]++;
            if (paymentsInBlock[msg.sender] > MAX_PAYMENTS_PER_BLOCK) revert RateLimitExceeded();
        }
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner whenPaused {
        IERC20(token).safeTransfer(owner(), amount);
        emit EmergencyWithdraw(token, amount, owner());
    }

    function getPayment(uint256 paymentId) external view returns (Payment memory) { return payments[paymentId]; }
    function getClaimableAmount(uint256 agentId) external view returns (uint256) { return pendingClaims[agentId]; }
}
