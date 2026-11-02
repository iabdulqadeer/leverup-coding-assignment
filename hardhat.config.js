const path = require("path");
const { subtask } = require("hardhat/config");
const { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } = require("hardhat/builtin-tasks/task-names");
require("@nomicfoundation/hardhat-ethers");

// The assignment keeps its contracts in the repo root, so list them explicitly.
const SOURCES = ["MockOracle.sol", "MockUSDC.sol", "PerpEngine.sol", "test/TestToken.sol"];

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, { config }) =>
  SOURCES.map((file) => path.join(config.paths.root, file))
);

module.exports = {
  solidity: "0.8.24",
};
