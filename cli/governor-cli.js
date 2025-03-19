
// governor-cli.js
const { Command } = require("commander");
const { ethers } = require("ethers");
const rlp = require("rlp");
require("dotenv").config();

const program = new Command();
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);

const governorAbi = [
  "function propose(address[] targets, uint256[] values, bytes[] calldatas, string description) returns (uint256)",
  "function proposalSnapshot(uint256 proposalId) view returns (uint256)"
];

const votingMachineAbi = [
  "function relayResult(bytes32 proposalId, address[] voters, uint256 gasLimit) external payable",
  "function voteWeight(bytes32 proposalId, address voter) view returns (uint256)",
  "function totalVotes(bytes32 proposalId) view returns (uint256)",
  "function voteWithProof(bytes32 proposalId, uint256 snapshotBlock, address token, address voter, uint256 slot, bytes calldata proof) external",
  "function processStorageRoot(address account, uint256 blockNumber, bytes calldata blockHeaderRLP, bytes calldata accountProof) external"
];

// PROPOSE
program
  .command("propose")
  .requiredOption("--governor <address>")
  .requiredOption("--targets <addresses>")
  .requiredOption("--values <amounts>")
  .requiredOption("--calldatas <hex-calls>")
  .requiredOption("--description <text>")
  .action(async (opts) => {
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const gov = new ethers.Contract(opts.governor, governorAbi, signer);

    const targets = opts.targets.split(",");
    const values = opts.values.split(",").map(v => ethers.BigNumber.from(v));
    const calldatas = opts.calldatas.split(",").map(x => x.startsWith("0x") ? x : "0x" + x);

    const tx = await gov.propose(targets, values, calldatas, opts.description);
    console.log("Proposal tx:", tx.hash);
  });

// GET SNAPSHOT BLOCK
program
  .command("get-snapshot")
  .requiredOption("--governor <address>")
  .requiredOption("--proposal-id <id>")
  .action(async (opts) => {
    const gov = new ethers.Contract(opts.governor, governorAbi, provider);
    const block = await gov.proposalSnapshot(opts.proposalId);
    console.log("Snapshot block:", block.toString());
  });

// PUBLISH STORAGE ROOT
program
  .command("publish-root")
  .requiredOption("--token <address>")
  .requiredOption("--block <number>")
  .requiredOption("--voting-machine <address>")
  .action(async (opts) => {
    const block = await provider.send("eth_getBlockByNumber", [
      ethers.utils.hexValue(parseInt(opts.block)),
      false
    ]);
    const blockHeaderRLP = rlp.encode([
      block.parentHash,
      block.sha3Uncles,
      block.miner,
      block.stateRoot,
      block.transactionsRoot,
      block.receiptsRoot,
      block.logsBloom,
      ethers.BigNumber.from(block.difficulty).toHexString(),
      ethers.BigNumber.from(block.number).toHexString(),
      ethers.BigNumber.from(block.gasLimit).toHexString(),
      ethers.BigNumber.from(block.gasUsed).toHexString(),
      ethers.BigNumber.from(block.timestamp).toHexString(),
      block.extraData,
      block.mixHash,
      block.nonce
    ]);

    const proof = await provider.send("eth_getProof", [
      opts.token,
      [],
      ethers.utils.hexValue(parseInt(opts.block))
    ]);

    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const vm = new ethers.Contract(opts.votingMachine, votingMachineAbi, signer);
    const tx = await vm.processStorageRoot(
      opts.token,
      parseInt(opts.block),
      blockHeaderRLP,
      ethers.utils.RLP.encode(proof.accountProof.map(p => ethers.utils.arrayify(p)))
    );
    console.log("processStorageRoot tx:", tx.hash);
  });

// VOTE WITH PROOF
program
  .command("vote")
  .requiredOption("--proposal-id <id>")
  .requiredOption("--snapshot-block <number>")
  .requiredOption("--token <address>")
  .requiredOption("--voter <address>")
  .requiredOption("--slot <number>")
  .requiredOption("--proof <hexproof>")
  .requiredOption("--voting-machine <address>")
  .action(async (opts) => {
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const vm = new ethers.Contract(opts.votingMachine, votingMachineAbi, signer);
    const proof = opts.proof.startsWith("0x") ? opts.proof : "0x" + opts.proof;

    const tx = await vm.voteWithProof(
      opts.proposalId,
      parseInt(opts.snapshotBlock),
      opts.token,
      opts.voter,
      parseInt(opts.slot),
      proof
    );
    console.log("voteWithProof tx:", tx.hash);
  });

// RELAY RESULT
program
  .command("relay-result")
  .requiredOption("--proposal-id <id>")
  .requiredOption("--voting-machine <address>")
  .requiredOption("--gas-limit <gas>")
  .requiredOption("--eth <amount>")
  .action(async (opts) => {
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const vm = new ethers.Contract(opts.votingMachine, votingMachineAbi, signer);
    const value = ethers.utils.parseEther(opts.eth);
    const tx = await vm.relayResult(opts.proposalId, [], ethers.BigNumber.from(opts.gasLimit), { value });
    console.log("relayResult tx:", tx.hash);
  });

// AGGREGATE VOTES LOCALLY
program
  .command("aggregate-votes")
  .requiredOption("--proposal-id <id>")
  .requiredOption("--voting-machine <address>")
  .requiredOption("--voters <list>")
  .action(async (opts) => {
    const vm = new ethers.Contract(opts.votingMachine, votingMachineAbi, provider);
    const voters = opts.voters.split(",").map((v) => v.trim());
    let total = ethers.BigNumber.from(0);
    for (const v of voters) {
      const weight = await vm.voteWeight(opts.proposalId, v);
      console.log(`Voter: ${v}, Weight: ${weight.toString()}`);
      total = total.add(weight);
    }
    console.log("---");
    console.log("Total voting power:", total.toString());
  });

program.parseAsync(process.argv);
