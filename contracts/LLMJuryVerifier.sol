// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "./interfaces/ILLMJuryVerifier.sol";
import "./TaskEscrow.sol";

contract LLMJuryVerifier is FunctionsClient, ConfirmedOwner, ILLMJuryVerifier {
    using FunctionsRequest for FunctionsRequest.Request;

    TaskEscrow public immutable escrow;

    bytes32 public donId;
    uint64 public subscriptionId;
    uint32 public gasLimit = 300000;
    string public source;

    mapping(bytes32 => uint256) public requestToTaskId;

    event JuryRequested(bytes32 indexed requestId, uint256 indexed taskId);
    event JuryFulfilled(bytes32 indexed requestId, uint256 indexed taskId, bool approved);

    error UnexpectedRequestID(bytes32 requestId);

    constructor(
        address router,
        address _escrow,
        bytes32 _donId,
        uint64 _subscriptionId,
        string memory _source
    ) FunctionsClient(router) ConfirmedOwner(msg.sender) {
        escrow = TaskEscrow(_escrow);
        donId = _donId;
        subscriptionId = _subscriptionId;
        source = _source;
    }

    function requestVerification(uint256 taskId) external override {
        require(msg.sender == address(escrow), "Only escrow");

        TaskEscrow.Task memory task = escrow.getTask(taskId);
        require(task.status == TaskEscrow.TaskStatus.Disputed, "Not disputed");

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);

        string[] memory args = new string[](5);
        args[0] = uint2str(taskId);
        args[1] = addressToString(address(escrow));
        args[2] = "Client claims incomplete"; // Placeholder - extend with real prompts
        args[3] = "Agent claims complete";
        args[4] = bytes32ToString(task.proofHash);
        req.setArgs(args);

        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donId
        );

        requestToTaskId[requestId] = taskId;
        emit JuryRequested(requestId, taskId);
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory) internal override {
        uint256 taskId = requestToTaskId[requestId];
        if (taskId == 0) revert UnexpectedRequestID(requestId);

        delete requestToTaskId[requestId];

        uint256 result = abi.decode(response, (uint256));
        bool approved = result == 1;

        escrow.resolveDispute(taskId, approved);
        emit JuryFulfilled(requestId, taskId, approved);
    }

    function updateConfig(bytes32 _donId, uint64 _subscriptionId, string calldata _source) external onlyOwner {
        donId = _donId;
        subscriptionId = _subscriptionId;
        source = _source;
    }

    // Helpers
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j!= 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i!= 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(66);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            str[2 + i * 2] = alphabet[uint8(_bytes32[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(_bytes32[i] & 0x0f)];
        }
        return string(str);
    }
}
