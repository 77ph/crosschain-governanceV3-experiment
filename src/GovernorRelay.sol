
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGovernor {
    function finalizeCrosschainVotes(bytes32 proposalId, uint256 votingPower) external;
}

interface IWormholeReceiver {
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalMessages,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external;
}

contract GovernorRelay is IWormholeReceiver {
    address public immutable governor;
    address public immutable wormholeRelayer;

    constructor(address _governor, address _wormholeRelayer) {
        governor = _governor;
        wormholeRelayer = _wormholeRelayer;
    }

    modifier onlyWormhole() {
        require(msg.sender == wormholeRelayer, "Not Wormhole relayer");
        _;
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32,
        uint16,
        bytes32
    ) external override onlyWormhole {
        (bytes32 proposalId, uint256 votePower) = abi.decode(payload, (bytes32, uint256));
        IGovernor(governor).finalizeCrosschainVotes(proposalId, votePower);
    }
}
