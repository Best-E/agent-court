// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface ITaskEscrow {
    function resolve(uint256 taskId, bool payerWon) external;
}

contract MockLLMJuryVerifier {
    ITaskEscrow public escrow;
    uint8 public mockVote = 3;
    uint256 public lastTaskId;

    constructor(address _escrow) {
        escrow = ITaskEscrow(_escrow);
    }

    function requestVerdict(uint256 taskId) external {
        lastTaskId = taskId;
    }

    function setVote(uint8 _vote) external {
        require(_vote <= 5, "Invalid vote");
        mockVote = _vote;
    }

    function fulfillMock(uint256 taskId) external {
        bool payerWon = mockVote < 3;
        escrow.resolve(taskId, payerWon);
    }
}
