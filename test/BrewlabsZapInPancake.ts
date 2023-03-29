import { loadFixture, mine } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";

describe("BrewlabsZapInPancake", function () {
  async function deployFixture() {
    const [owner, accountA, accountB] = await ethers.getSigners();

    const WBNB = await ethers.getContractFactory("WBNB");
    const wbnb = await WBNB.deploy();

    const PancakeFactory = await ethers.getContractFactory("PancakeFactory");
    const pancakeFactory = await PancakeFactory.deploy(owner.address);

    const PancakeRouter = await ethers.getContractFactory("PancakeRouter");
    const pancakeRouter = await PancakeRouter.deploy(pancakeFactory.address, wbnb.address);

    const BEP20Token = await ethers.getContractFactory("BEP20Token");
    const busd = await BEP20Token.deploy();

    const IterableMapping = await ethers.getContractFactory("IterableMapping");
    const iterableMapping = await IterableMapping.deploy();

    const Brewlabs = await ethers.getContractFactory("Brewlabs", {
      libraries: {
        IterableMapping: iterableMapping.address
      }
    });
    const brewlabs = await Brewlabs.deploy();

    const BrewlabsLiquidityManager = await ethers.getContractFactory("BrewlabsLiquidityManager");
    const brewlabsLiquidityManager = await BrewlabsLiquidityManager.deploy();

    const BrewlabsZapInPancake = await ethers.getContractFactory("BrewlabsZapInPancakeV2");
    const brewlabsZapInPancake = await BrewlabsZapInPancake.deploy('3500000000000000', owner.address);

    const CakeToken = await ethers.getContractFactory("contracts/CakeToken.sol:CakeToken");
    const cakeToken = await CakeToken.deploy();

    const SyrupBar = await ethers.getContractFactory("contracts/SyrupBar.sol:SyrupBar");
    const syrupBar = await SyrupBar.deploy(cakeToken.address);

    const MasterChef = await ethers.getContractFactory("MasterChef");
    const masterChef = await MasterChef.deploy(cakeToken.address, syrupBar.address, owner.address, "400000000000000000", 0);

    const MockBEP20 = await ethers.getContractFactory("MockBEP20");
    const mockBEP20 = await MockBEP20.deploy("dMCV2", "dMCV2", "10000000000000000000");

    const MasterChefV2 = await ethers.getContractFactory("MasterChefV2");
    const masterChefV2 = await MasterChefV2.deploy(masterChef.address, cakeToken.address, 1, owner.address);

    return {
      wbnb,
      pancakeFactory,
      pancakeRouter,
      busd,
      brewlabs,
      brewlabsLiquidityManager,
      brewlabsZapInPancake,
      cakeToken,
      syrupBar,
      masterChef,
      mockBEP20,
      masterChefV2,
      owner,
      accountA,
      accountB
    };
  }

  describe("Deployment", function () {
    it("Should deploy all the contracts", async function () {
      const {
        wbnb,
        pancakeFactory,
        pancakeRouter,
        cakeToken,
        masterChefV2,
        brewlabs,
        brewlabsLiquidityManager
      } = await loadFixture(deployFixture);
      // console.log('pancakeswapFactory', pancakeFactory.address);
      // console.log('pancakeswapRouter', pancakeRouter.address);
      // console.log('brewlabsLiquidityManager', brewlabsLiquidityManager.address);
      // console.log('masterChefV2', masterChefV2.address);
      // console.log('cake', cakeToken.address);
      // console.log('wbnbTokenAddress', wbnb.address);
      // console.log('brewlabs address', brewlabs.address);
    });
  });

  describe("Zap", function () {
    it("Should zap in", async function () {
      const { wbnb, busd, brewlabs, pancakeFactory, pancakeRouter, brewlabsZapInPancake, brewlabsLiquidityManager, cakeToken, syrupBar, masterChef, mockBEP20, masterChefV2, owner, accountA, accountB } = await loadFixture(deployFixture);

      await cakeToken["mint(uint256)"]("13363594647357063967");
      await cakeToken.approve(pancakeRouter.address, "13363594647357063967");
      await pancakeRouter.addLiquidityETH(
        cakeToken.address,
        "13363594647357063967",
        0,
        0,
        owner.address,
        "0xf000000000000000000000000000000000000000000000000000000000000000",
        {
          value: '3171896323161505191'
        }
      );

      await busd.approve(pancakeRouter.address, "850087142821752331008");
      await pancakeRouter.addLiquidityETH(
        busd.address,
        "850087142821752331008",
        0,
        0,
        owner.address,
        "0xf000000000000000000000000000000000000000000000000000000000000000",
        {
          value: '2956970724705941490'
        }
      );

      await cakeToken.transferOwnership(masterChef.address);
      await syrupBar.transferOwnership(masterChef.address);

      let allocPoint = 1;
      await masterChef.add(allocPoint, mockBEP20.address, true);

      await mockBEP20.approve(masterChefV2.address, "10000000000000000000");
      await masterChefV2.init(mockBEP20.address);

      const cakeBnb = await pancakeFactory.getPair(cakeToken.address, wbnb.address);
      await masterChefV2.add(allocPoint, cakeBnb, true, true);

      await brewlabsLiquidityManager.initialize(
        pancakeRouter.address,
        [wbnb.address, brewlabs.address]
      );

      await brewlabsZapInPancake.connect(accountA).zapIn(
        '0x0000000000000000000000000000000000000000',
        cakeBnb,
        "0",
        "10000000000000000",
        "0",
        cakeToken.address,
        {
          value: "13500000000000000"
        }
      );
      await mine(9);
      await busd.transfer(accountB.address, '120000000000000000000');
      await busd.connect(accountB).approve(brewlabsZapInPancake.address, '120000000000000000000');
      await brewlabsZapInPancake.connect(accountB).zapIn(
        busd.address,
        cakeBnb,
        "0",
        "120000000000000000000",
        "0",
        cakeToken.address,
        {
          value: "3500000000000000"
        }
      );
      await mine(4);
      await brewlabsZapInPancake.connect(accountA).zapOut(0, 0, cakeToken.address, { value: '3500000000000000' });
      await mine(9);
      await brewlabsZapInPancake.connect(accountB).zapOut(0, 0, cakeToken.address, { value: '3500000000000000' });
      await mine(4);
      await brewlabsZapInPancake.connect(accountA).zapOut(0, 0, cakeToken.address, { value: '3500000000000000' });
      await brewlabsZapInPancake.connect(accountB).zapOut(0, 0, cakeToken.address, { value: '3500000000000000' });
      console.log('totalRewardsA', (await brewlabsZapInPancake.userInfo(0, accountA.address)).totalRewards.toString());
      console.log('totalRewardsB', (await brewlabsZapInPancake.userInfo(0, accountB.address)).totalRewards.toString());
      console.log('totalRewards', (await brewlabsZapInPancake.poolInfo(0)).totalRewards.toString());
    });
  });

})