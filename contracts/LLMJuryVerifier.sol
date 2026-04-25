// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./TaskEscrow.sol";

contract LLMJuryVerifier is Ownable {
    TaskEscrow public immutable ESCROW;
    address public chainlinkOracle;

    event JuryRequested(uint256 indexed taskId);
    event JuryFulfilled(uint256 indexed taskId, bool payerWon);

    constructor(address _escrow) Ownable(msg.sender) {
        ESCROW = TaskEscrow(_escrow);
    }

    function setOracle(address _oracle) external onlyOwner {
        chainlinkOracle = _oracle;
    }

    function requestJury(uint256 taskId) external {
        (,,,,,, TaskEscrow.Status status, ) = ESCROW.tasks(taskId);
        require(status == TaskEscrow.Status.Disputed, "Not disputed");
        emit JuryRequested(taskId);
    }

    function fulfillJury(uint256 taskId, bool payerWon) external {
        require(msg.sender == chainlinkOracle, "Not oracle");
        ESCROW.resolve(taskId, payerWon);
        emit JuryFulfilled(taskId, payerWon);
    }
}
