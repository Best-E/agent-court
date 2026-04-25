// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../interfaces/ILLMJuryVerifier.sol";
import "../TaskEscrow.sol";

contract MockLLMJuryVerifier is ILLMJuryVerifier {
    TaskEscrow public immutable escrow;
    address public owner;
    
    // For testing: control the jury outcome
    bool public autoApprove = true;
    bool public shouldRevert = false;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address _escrow) {
        escrow = TaskEscrow(_escrow);
        owner = msg.sender;
    }

    function requestVerification(uint256 taskId) external override {
        if (shouldRevert) revert("Mock: Forced revert");
        
        // Instant response for tests
        escrow.resolveDispute(taskId, autoApprove);
    }

    // Test helpers
    function setAutoApprove(bool _approve) external onlyOwner {
        autoApprove = _approve;
    }

    function setShouldRevert(bool _revert) external onlyOwner {
        shouldRevert = _revert;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
