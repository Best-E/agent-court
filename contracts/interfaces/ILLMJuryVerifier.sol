// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface ILLMJuryVerifier {
    function requestVerification(uint256 taskId) external;
}
