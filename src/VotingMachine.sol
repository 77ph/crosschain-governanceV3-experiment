// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RLPReader} from "./RLPReader.sol";
import {MerklePatriciaProofVerifier} from "./MerklePatriciaProofVerifier.sol";

interface IWormholeRelayer {
    function sendPayloadToEvm(
        uint16 targetChain,
        bytes32 targetAddress,
        bytes calldata payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence);
}

contract VotingMachine {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.RLPItem[];

    mapping(address => mapping(uint256 => bytes32)) public storageRoots;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;
    mapping(bytes32 => mapping(address => uint256)) public voteWeight;
    mapping(bytes32 => uint256) public proposalSnapshots;

    uint8 constant ACCOUNT_STORAGE_ROOT_INDEX = 2;

    address public immutable wormholeRelayer;
    uint16 public immutable targetChainId;
    bytes32 public immutable l1ReceiverAddress;

    constructor(address _relayer, uint16 _targetChainId, bytes32 _l1Receiver) {
        wormholeRelayer = _relayer;
        targetChainId = _targetChainId;
        l1ReceiverAddress = _l1Receiver;
    }

    function registerSnapshot(bytes32 proposalId, uint256 snapshotBlock) external {
        require(proposalSnapshots[proposalId] == 0, "Snapshot already set");
        proposalSnapshots[proposalId] = snapshotBlock;
    }

    function processStorageRoot(
        address account,
        uint256 blockNumber,
        bytes memory blockHeaderRLP,
        bytes memory accountStateProofRLP
    ) public {
        bytes32 blockHash = blockhash(blockNumber);
        require(blockHash != bytes32(0), "Blockhash not available");

        bytes32 stateRoot = getStateRootFromHeader(blockHeaderRLP, blockHash);
        bytes32 proofPath = keccak256(abi.encodePacked(account));

        bytes memory accountRLP = MerklePatriciaProofVerifier.extractProofValue(
            stateRoot,
            proofPath,
            accountStateProofRLP
        );

        RLPReader.RLPItem[] memory decoded = accountRLP.toRLPItem().toList();
        bytes32 accountStorageRoot = bytes32(decoded[ACCOUNT_STORAGE_ROOT_INDEX].toUint());

        storageRoots[account][blockNumber] = accountStorageRoot;
    }

    function voteWithProof(
        bytes32 proposalId,
        uint256 snapshotBlock,
        address token,
        address voter,
        uint256 slot,
        bytes memory storageProof
    ) external {
        require(!hasVoted[proposalId][voter], "Already voted");
        require(snapshotBlock == proposalSnapshots[proposalId], "Snapshot mismatch");

        bytes32 storageRoot = storageRoots[token][snapshotBlock];
        require(storageRoot != bytes32(0), "Storage root not available");

        bytes32 storageKey = keccak256(abi.encodePacked(slot));
        bytes memory value = MerklePatriciaProofVerifier.extractProofValue(
            storageRoot,
            storageKey,
            storageProof
        );

        uint256 power = value.toRLPItem().toUint();
        voteWeight[proposalId][voter] = power;
        hasVoted[proposalId][voter] = true;
    }

    function relayResult(bytes32 proposalId, address[] calldata voters, uint256 gasLimit) external payable {
        uint256 total;
        for (uint256 i = 0; i < voters.length; i++) {
            total += voteWeight[proposalId][voters[i]];
        }

        bytes memory payload = abi.encode(proposalId, total);

        IWormholeRelayer(wormholeRelayer).sendPayloadToEvm{value: msg.value}(
            targetChainId,
            l1ReceiverAddress,
            payload,
            0,
            gasLimit
        );
    }

    function getStateRootFromHeader(bytes memory rlp, bytes32 expectedHash) public pure returns (bytes32) {
        require(keccak256(rlp) == expectedHash, "Header hash mismatch");
        RLPReader.RLPItem[] memory header = rlp.toRLPItem().toList();
        return bytes32(header[3].toUint());
    }
}
