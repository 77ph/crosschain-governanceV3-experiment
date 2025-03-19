
// governor-cli.js
const { Command } = require("commander");
const { ethers } = require("ethers");
require("dotenv").config();

const program = new Command();
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);

const votingMachineAbi = [
  "function relayResult(bytes32 proposalId, address[] voters, uint256 gasLimit) external payable"
];

program
  .command("relay-result")
  .requiredOption("--proposal-id <id>")
  .requiredOption("--voters <list>")
  .requiredOption("--voting-machine <address>")
  .requiredOption("--gas-limit <gas>")
  .requiredOption("--eth <amount>")
  .action(async (opts) => {
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const vm = new ethers.Contract(opts.votingMachine, votingMachineAbi, signer);

    const voters = opts.voters.split(",").map((v) => v.trim());
    const proposalId = opts.proposalId;
    const gasLimit = ethers.BigNumber.from(opts.gasLimit);
    const value = ethers.utils.parseEther(opts.eth);

    const tx = await vm.relayResult(proposalId, voters, gasLimit, { value });
    console.log("relayResult tx:", tx.hash);
  });

program.parseAsync(process.argv);
