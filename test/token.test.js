const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Token", function () {
  it("Should deploy the token", async function () {
    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy("Value Network", "VNTW");
    await token.deployed();

    expect(await token.name()).to.equal("Value Network");
    expect(await token.symbol()).to.equal("VNTW");

    const setBurnRateTx = await token.setBurnRate(500);

    // wait until the transaction is mined
    await setBurnRateTx.wait();

    expect(await token.burnRate()).to.equal(500);
  });
});
