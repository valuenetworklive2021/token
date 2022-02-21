const hre = require("hardhat");

async function main() {
  // We get the contract to deploy
  const Token = await hre.ethers.getContractFactory("Token");
  const token = await Token.deploy("Token", "TKN");

  await token.deployed();

  console.log("token deployed to:", token.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
