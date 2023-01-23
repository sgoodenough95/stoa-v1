import { ethers } from "hardhat";

async function main() {

    const MAX_UINT = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

    const ActivatedToken = await ethers.getContractFactory("OldActivatedToken");
    const UnactivatedToken = await ethers.getContractFactory("UnactivatedToken");
    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const TestVault = await ethers.getContractFactory("TestVault");
    const Treasury = await ethers.getContractFactory("Treasury");
    const ActivePool = await ethers.getContractFactory("ActivePool");
    const PriceFeed = await ethers.getContractFactory("PriceFeed");
    const SafeManager = await ethers.getContractFactory("SafeManager");
    const Controller = await ethers.getContractFactory("Controller");
    const SafeOps = await ethers.getContractFactory("SafeOperations");

    const USDSTa = await ActivatedToken.deploy("Stoa Activated Dollar", "USDSTa");
    console.log("export const USDSTaAddress == ", USDSTa.address);
    const ETHSTa = await ActivatedToken.deploy("Stoa Activated Ethereum", "ETHSTa");
    console.log("export const ETHSTaAddress ==", ETHSTa.address);
    const USDST = await UnactivatedToken.deploy("Stoa Dollar", "USDST");
    console.log("export const USDSTAddress ==", USDST.address);
    const ETHST = await UnactivatedToken.deploy("Stoa Ethereum", "ETHST");
    console.log("export const ETHSTAddress ==", ETHST.address);
    const testDAI = await TestERC20.deploy("Test DAI", "tDAI", "10000000000000000000000");    // 10,000 DAI
    console.log("export const testDAIAddress ==", testDAI.address);
    const testETH = await TestERC20.deploy("Test ETH", "tETH", "100000000000000000000");    // 10 ETH
    console.log("Test ETH contract deployed to: ", testETH.address);
    const testDAIVault = await TestVault.deploy(testDAI.address, testDAI.address, "Test yvDAI", "tyvDAI");
    console.log("Test DAI Vault contract deployed to: ", testDAIVault.address);
    const testETHVault = await TestVault.deploy(testETH.address, testETH.address, "Test yvETH", "tyvETH");
    console.log("Test ETH Vault contract deployed to: ", testETHVault.address);
    const treasury = await Treasury.deploy();
    console.log("Treasury contract deployed to: ", treasury.address);
    const USDSTaPool = await ActivePool.deploy(USDSTa.address, "Active Pool USDSTa", "apUSDSTa");
    console.log("USDSTa Active Pool contract deployed to: ", USDSTaPool.address);
    const ETHSTaPool = await ActivePool.deploy(ETHSTa.address, "Active Pool ETHSTa", "apETHSTa");
    console.log("ETHSTa Active Pool contract deployed to: ", ETHSTaPool.address);
    const priceFeed = await PriceFeed.deploy();
    console.log("Price Feed contract deployed to: ", priceFeed.address);
    const safeManager = await SafeManager.deploy(priceFeed.address);
    console.log("Safe Manager contract deployed to: ", safeManager.address);
    const USDController = await Controller.deploy(
        testDAIVault.address,
        treasury.address,
        safeManager.address,
        testDAI.address,
        USDSTa.address,
        USDST.address
    );
    console.log("USD Controller contract deployed to: ", USDController.address);
    const ETHController = await Controller.deploy(
        testETHVault.address,
        treasury.address,
        safeManager.address,
        testETH.address,
        ETHSTa.address,
        ETHST.address
    );
    console.log("ETH Controller contract deployed to: ", ETHController.address);
    const safeOps = await SafeOps.deploy(safeManager.address, priceFeed.address, treasury.address);
    console.log("Safe Ops contract deployed to: ", safeOps.address);

    await USDController.rebaseOptIn(USDSTa.address);
    await ETHController.rebaseOptIn(ETHSTa.address);
    await treasury.rebaseOptIn(USDSTa.address);
    await treasury.rebaseOptIn(ETHSTa.address);
    await USDSTaPool.rebaseOptIn();
    await ETHSTaPool.rebaseOptIn();
    console.log("Rebase opt-ins complete");

    // Change to set yield venue
    await safeOps.setController(testDAI.address, USDController.address);
    await safeOps.setController(USDSTa.address, USDController.address);
    await safeOps.setController(testETH.address, ETHController.address);
    await safeOps.setController(ETHSTa.address, ETHController.address);
    await safeManager.setSafeOps(safeOps.address);
    await USDController.setSafeOps(safeOps.address);
    await ETHController.setSafeOps(safeOps.address);
    await USDController.setSafeManager(safeManager.address);
    await ETHController.setSafeManager(safeManager.address);
    await safeManager.setActivePool(USDSTa.address, USDSTaPool.address);
    await safeManager.setActivePool(ETHSTa.address, ETHSTaPool.address);
    await safeManager.setUnactiveCounterpart(USDSTa.address, USDST.address);
    await safeManager.setUnactiveCounterpart(ETHSTa.address, ETHST.address);
    await safeManager.setActiveToDebtTokenMCR(USDSTa.address, USDST.address, "20000");
    await safeManager.setActiveToDebtTokenMCR(ETHSTa.address, ETHST.address, "20000");
    await safeManager.setActiveToDebtTokenMCR(ETHSTa.address, USDST.address, "15000");
    await safeManager.setPriceFeed(priceFeed.address);
    await priceFeed.setPrice(USDSTa.address, "1000000000000000000");    // $1
    await priceFeed.setPrice(USDST.address, "1000000000000000000"); // $1
    await priceFeed.setPrice(ETHSTa.address, "1500000000000000000000");    // $1,500
    await priceFeed.setPrice(ETHST.address, "1500000000000000000000"); // $1,500
    console.log("Setup complete");

    await treasury.approveToken(USDSTa.address, safeOps.address);
    await treasury.approveToken(USDSTa.address, USDController.address);
    await treasury.approveToken(ETHSTa.address, safeOps.address);
    await treasury.approveToken(ETHSTa.address, ETHController.address);
    await USDController.approveToken(USDSTa.address, USDSTaPool.address);
    await ETHController.approveToken(ETHSTa.address, ETHSTaPool.address);
    await testDAI.approve(testDAIVault.address, MAX_UINT);
    await testETH.approve(testETHVault.address, MAX_UINT);
    await USDSTa.approve(USDController.address, MAX_UINT);
    await USDSTa.approve(USDSTaPool.address, MAX_UINT);
    await USDSTa.approve(safeOps.address, MAX_UINT);
    await USDST.approve(USDController.address, MAX_UINT);
    await USDST.approve(safeOps.address, MAX_UINT);
    await ETHSTa.approve(ETHController.address, MAX_UINT);
    await ETHSTa.approve(ETHSTaPool.address, MAX_UINT);
    await ETHSTa.approve(safeOps.address, MAX_UINT);
    await ETHST.approve(ETHController.address, MAX_UINT);
    await ETHST.approve(safeOps.address, MAX_UINT);
    console.log("Approvals complete");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });