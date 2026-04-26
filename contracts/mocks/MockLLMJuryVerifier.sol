// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../interfaces/ILLMJuryVerifier.sol";
import "../TaskEscrow.sol";

contract MockLLMJuryVerifier is ILLMJuryVerifier {
    TaskEscrow public immutable escrow;
    bool public defaultVerdict; // true = client wins, false = agent wins
    mapping(uint256 => bool) public customVerdicts;
    mapping(uint256 => bool) public hasCustomVerdict;

    event MockJuryCalled(uint256 indexed taskId, bool clientWon);

    constructor(address _escrow, bool _defaultVerdict) {
        escrow = TaskEscrow(_escrow);
        defaultVerdict = _defaultVerdict;
    }

    function requestVerification(uint256 taskId) external override {
        require(msg.sender == address(escrow), "Only escrow");

        bool clientWon = hasCustomVerdict[taskId]
          ? customVerdicts[taskId]
            : defaultVerdict;

        emit MockJuryCalled(taskId, clientWon);

        // Immediately resolve - no Chainlink delay
        escrow.resolveDispute(taskId, clientWon);
    }

    function setVerdict(uint256 taskId, bool clientWins) external {
        customVerdicts[taskId] = clientWins;
        hasCustomVerdict[taskId] = true;
    }

    function setDefaultVerdict(bool clientWins) external {
        defaultVerdict = clientWins;
    }
}
