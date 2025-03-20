// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "aragon/packages/evm/contracts/lib/RLP.sol";
import "aragon/packages/evm/contracts/lib/TrieProofs.sol";

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
    using RLP for bytes;
    using RLP for RLP.RLPItem;
    using RLP for RLP.RLPItem[];

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

    function encodeList(bytes[] memory items) internal pure returns (bytes memory) {
        bytes memory payload;
        for (uint256 i = 0; i < items.length; i++) {
            payload = bytes.concat(payload, items[i]);
        }
        return abi.encodePacked(encodeLength(payload.length, 192), payload);
    }

    function encodeLength(uint256 len, uint256 offset) internal pure returns (bytes memory) {
        if (len < 56) {
            return abi.encodePacked(uint8(len + offset));
        } else {
            uint256 lenLen;
            uint256 i = len;
            while (i != 0) {
                lenLen++;
                i = i >> 8;
            }

            bytes memory b = new bytes(lenLen);
            for (uint256 j = 0; j < lenLen; ++j) {
                b[lenLen - 1 - j] = bytes1(uint8(len >> (8 * j)));
            }

            return abi.encodePacked(uint8(offset + 55 + lenLen), b);
        }
    }

    function registerSnapshot(bytes32 proposalId, uint256 snapshotBlock) external {
        require(proposalSnapshots[proposalId] == 0, "Snapshot already set");
        proposalSnapshots[proposalId] = snapshotBlock;
    }

    function processStorageRoot(
        address account,
        uint256 blockNumber,
        bytes memory blockHeaderRLP,
        bytes[] memory accountProof
    ) public {
        bytes32 blockHash = blockhash(blockNumber);
        require(blockHash != bytes32(0), "Blockhash not available");

        bytes32 stateRoot = getStateRootFromHeader(blockHeaderRLP, blockHash);
        bytes32 proofPath = keccak256(abi.encodePacked(account));

        // ✨ RLP-энкодим bytes[] в bytes
        bytes memory encodedProof = encodeList(accountProof);

        // ✅ Используем TrieProofs.verify(...)
        bytes memory accountRLP = TrieProofs.verify(encodedProof, stateRoot, proofPath);

        RLP.RLPItem[] memory decoded = accountRLP.toRLPItem().toList();
        bytes32 accountStorageRoot = bytes32(decoded[ACCOUNT_STORAGE_ROOT_INDEX].toUint());

        storageRoots[account][blockNumber] = accountStorageRoot;
    }

    function voteWithProof(
        bytes32 proposalId,
        uint256 snapshotBlock,
        address token,
        address voter,
        uint256 slot,
        bytes[] memory storageProof
    ) external {
        require(!hasVoted[proposalId][voter], "Already voted");
        require(snapshotBlock == proposalSnapshots[proposalId], "Snapshot mismatch");

        bytes32 storageRoot = storageRoots[token][snapshotBlock];
        require(storageRoot != bytes32(0), "Storage root not available");

        // 🔑 Вычисляем ключ для storage
        bytes32 storageKey = keccak256(abi.encodePacked(slot));

        // ✨ Кодируем proof как RLP-список
        bytes memory encodedProof = encodeList(storageProof);

        // ✅ Используем библиотеку Aragon
        bytes memory value = TrieProofs.verify(encodedProof, storageRoot, storageKey);

        // 🗳️ Извлекаем голосовую силу (uint256)
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
            targetChainId, l1ReceiverAddress, payload, 0, gasLimit
        );
    }

    function getStateRootFromHeader(bytes memory rlp, bytes32 expectedHash) public pure returns (bytes32) {
        require(keccak256(rlp) == expectedHash, "Header hash mismatch");
        RLP.RLPItem[] memory header = rlp.toRLPItem().toList();
        return bytes32(header[3].toUint());
    }
}
