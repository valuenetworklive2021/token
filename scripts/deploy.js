const hre = require("hardhat");

async function main() {
  // We get the contract to deploy
  const Token = await hre.ethers.getContractFactory("Token");
  const Vesting = await hre.ethers.getContractFactory("Vesting");
  const DevPool = await hre.ethers.getContractFactory("DevPool");

  const token = await Token.deploy("Token", "TKN");
  await token.deployed();

  const vesting = await Vesting.deploy(token.address);
  await vesting.deployed();

  const devpool = await DevPool.deploy([], 2, vesting.address);
  await devpool.deployed();

  console.log("token deployed to:", token.address);
  console.log("vesting deployed to:", vesting.address);
  console.log("devpool deployed to:", devpool.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
