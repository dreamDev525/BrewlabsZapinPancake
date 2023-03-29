import { ethers } from "hardhat";

async function main() {
  const feeAmount = "3500000000000000";
  const feeAddress = "0x408c4aDa67aE1244dfeC7D609dea3c232843189A";

  const BrewlabsZapInPancake = await ethers.getContractFactory("BrewlabsZapInPancakeV2");
  const brewlabsZapInPancake = await BrewlabsZapInPancake.deploy(feeAmount, feeAddress);

  await brewlabsZapInPancake.deployed();

  console.log("BrewlabsZapInPancake deployed to:", brewlabsZapInPancake.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
