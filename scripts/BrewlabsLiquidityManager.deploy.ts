import { ethers } from "hardhat";

async function main() {
  const BrewlabsLiquidityManager = await ethers.getContractFactory("BrewlabsLiquidityManager");
  const brewlabsLiquidityManager = await BrewlabsLiquidityManager.deploy();

  await brewlabsLiquidityManager.deployed();

  console.log("BrewlabsLiquidityManager deployed to:", brewlabsLiquidityManager.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
