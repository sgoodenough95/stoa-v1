import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ActivePool__factory, Controller__factory, Treasury__factory } from "../typechain-types";

const hre = require("hardhat");

describe("Safe", function () {

    async function deployContracts() {

        const [owner] = await ethers.getSigners();
        const MAX_UINT = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

        const ActivatedToken = await ethers.getContractFactory("ActivatedToken");
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
        const ETHSTa = await ActivatedToken.deploy("Stoa Activated Ethereum", "ETHSTa");
        const USDST = await UnactivatedToken.deploy("Stoa Dollar", "USDST");
        const ETHST = await UnactivatedToken.deploy("Stoa Ethereum", "ETHST");
        const testDAI = await TestERC20.deploy("Test DAI", "tDAI", "10000000000000000000000");    // 10,000 DAI
        const testETH = await TestERC20.deploy("Test ETH", "tETH", "100000000000000000000");    // 10 ETH
        const testDAIVault = await TestVault.deploy(testDAI.address, testDAI.address, "Test yvDAI", "tyvDAI");
        const testETHVault = await TestVault.deploy(testETH.address, testETH.address, "Test yvETH", "tyvETH");
        const treasury = await Treasury.deploy();
        const USDSTaPool = await ActivePool.deploy(USDSTa.address, "Active Pool USDSTa", "apUSDSTa");
        const ETHSTaPool = await ActivePool.deploy(ETHSTa.address, "Active Pool ETHSTa", "apETHSTa");
        const priceFeed = await PriceFeed.deploy();
        const safeManager = await SafeManager.deploy(priceFeed.address);
        const USDController = await Controller.deploy(
            testDAIVault.address,
            treasury.address,
            safeManager.address,
            testDAI.address,
            USDSTa.address,
            USDST.address
        );
        const ETHController = await Controller.deploy(
            testETHVault.address,
            treasury.address,
            safeManager.address,
            testETH.address,
            ETHSTa.address,
            ETHST.address
        );
        const safeOps = await SafeOps.deploy(safeManager.address, priceFeed.address, treasury.address);

        await USDController.rebaseOptIn(USDSTa.address);
        await ETHController.rebaseOptIn(ETHSTa.address);
        await treasury.rebaseOptIn(USDSTa.address);
        await treasury.rebaseOptIn(ETHSTa.address);
        await USDSTaPool.rebaseOptIn();
        await ETHSTaPool.rebaseOptIn();

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

        return { 
            owner, USDSTa, USDST, ETHSTa, ETHST, testDAI, testDAIVault, testETH, testETHVault, priceFeed,
            USDController, ETHController, treasury, USDSTaPool, ETHSTaPool, safeManager, safeOps
        };
    }

    describe("Borrow actions", function () {

        it("Should open Safe", async function () {

            const {
                owner, testDAI, safeOps, safeManager, USDST, USDSTa, USDController, priceFeed,
                treasury, USDSTaPool, ETHST, testETH, ETHSTa, ETHController
            } = await loadFixture(deployContracts);

            await safeOps.openSafe(testETH.address, "100000000000000000000");

            await safeOps.borrow(0, USDST.address, "60000000000000000000000", true);

            console.log(await safeManager.isUnderwater(owner.address, 0));

            // Change ETH price from $1,500 to $500
            await priceFeed.setPrice(ETHSTa.address, "500000000000000000000");

            console.log(await safeManager.isUnderwater(owner.address, 0));

            // console.log(await safeManager.getSafeVal(owner.address, 0));
            // console.log(await safeManager.getSafeInit(owner.address, 0));
            // console.log(await safeManager.getSafeStatus(owner.address, 0));
        })
    })
    
    // describe("Rebase Opt-in", function () {

    //     it("Controller should opt-in", async function () {

    //         const { activatedToken, controller } = await loadFixture(deployContracts);

    //         expect(await activatedToken.rebaseState(controller.address)).to.equal(2);
    //     });

    //     it("Treasury should opt-in", async function () {

    //         const { activatedToken, treasury } = await loadFixture(deployContracts);

    //         expect(await activatedToken.rebaseState(treasury.address)).to.equal(2);
    //     });
    // });

    // describe("Controller-only actions", function () {

    //     // it("Should do non-custodial mint USDSTa with DAI", async function () {

    //     //     const { controller, owner, activatedToken, testDAI, testVault, treasury } = await loadFixture(deployContracts);

    //     //     const shares = await controller.deposit(owner.address, "10000000000000000000000", true);
    //     //     console.log("yvDAI: " + shares);

    //     //     const userUSDSTaBal = await activatedToken.balanceOf(owner.address);
    //     //     console.log("User USDSTa bal: " + userUSDSTaBal);

    //     //     const treasuryUSDSTaBal = await activatedToken.balanceOf(treasury.address);
    //     //     console.log("Treasury USDSTa bal: " + treasuryUSDSTaBal);

    //     //     const vaultDAIBal = await testDAI.balanceOf(testVault.address);
    //     //     console.log("Test Vault DAI bal: " + vaultDAIBal);
    //     // });

    //     // it("Should do non-custodial mint USDST with DAI", async function () {

    //     //     const { controller, owner, activatedToken, unactivatedToken, testDAI, testVault, treasury } = await loadFixture(deployContracts);

    //     //     const shares = await controller.deposit(owner.address, "10000000000000000000000", false);
    //     //     console.log("yvDAI: " + shares);

    //     //     const userUSDSTBal = await unactivatedToken.balanceOf(owner.address);
    //     //     console.log("User USDSTa bal: " + userUSDSTBal);

    //     //     const treasuryUSDSTaBal = await activatedToken.balanceOf(treasury.address);
    //     //     console.log("Treasury USDSTa bal: " + treasuryUSDSTaBal);
    //     //     expect(treasuryUSDSTaBal).to.equal('10000000000000000000000');

    //     //     const vaultDAIBal = await testDAI.balanceOf(testVault.address);
    //     //     console.log("Test Vault DAI bal: " + vaultDAIBal);
    //     // });

    //     // it("Should redeem DAI for USDSTa", async function () {

    //     //     const { controller, owner, activatedToken, unactivatedToken, testDAI, testVault, treasury } = await loadFixture(deployContracts);

    //     //     const shares = await controller.deposit(owner.address, "10000000000000000000000", true);
    //     //     console.log("yvDAI: " + shares);

    //     //     const userUSDSTaBalT0 = await activatedToken.balanceOf(owner.address);
    //     //     console.log("User USDSTa bal: " + userUSDSTaBalT0);

    //     //     const treasuryUSDSTaBal = await activatedToken.balanceOf(treasury.address);
    //     //     console.log("Treasury USDSTa bal: " + treasuryUSDSTaBal);

    //     //     const vaultDAIBal = await testDAI.balanceOf(testVault.address);
    //     //     console.log("Test Vault DAI bal: " + vaultDAIBal);

    //     //     const treasuryBackingReserveT0 = await treasury.backingReserve(activatedToken.address, unactivatedToken.address);
    //     //     console.log(treasuryBackingReserveT0);

    //     //     await testVault.simulateYield();
    //     //     await controller.rebase();

    //     //     const userUSDSTaBalT1 = await activatedToken.balanceOf(owner.address);
    //     //     console.log("User USDSTa bal: " + userUSDSTaBalT1);

    //     //     await controller.withdraw(owner.address, userUSDSTaBalT1.toString());
    //     //     console.log("Treasury USDSTa bal: " + await activatedToken.balanceOf(treasury.address));
    //     // });

    //     // it("Should convert USDSTa to USDST", async function () {

    //     //     const { controller, owner, activatedToken, unactivatedToken, testDAI, testVault, treasury } = await loadFixture(deployContracts);

    //     //     await controller.deposit(owner.address, "10000000000000000000000", true);

    //     //     const userUSDSTaBalT0 = await activatedToken.balanceOf(owner.address);
    //     //     console.log("User USDSTa bal: " + userUSDSTaBalT0);

    //     //     const treasuryUSDSTaBal = await activatedToken.balanceOf(treasury.address);
    //     //     console.log("Treasury USDSTa bal: " + treasuryUSDSTaBal);

    //     //     const vaultDAIBal = await testDAI.balanceOf(testVault.address);
    //     //     console.log("Test Vault DAI bal: " + vaultDAIBal);

    //     //     const treasuryBackingReserveT0 = await treasury.backingReserve(unactivatedToken.address, activatedToken.address);
    //     //     console.log(treasuryBackingReserveT0);

    //     //     await controller.activeToUnactive(userUSDSTaBalT0.toString());

    //     //     // await testVault.simulateYield();
    //     //     // await controller.rebase();

    //     //     const userUSDSTBal = await unactivatedToken.balanceOf(owner.address);
    //     //     console.log("User USDST bal: " + userUSDSTBal);

    //     //     const treasuryBackingReserveT1 = await treasury.backingReserve(unactivatedToken.address, activatedToken.address);
    //     //     console.log(treasuryBackingReserveT1);

    //     //     const treasuryUSDSTaBalT1 = await activatedToken.balanceOf(treasury.address);
    //     //     console.log("Treasury USDSTa bal: " + treasuryUSDSTaBalT1);

    //     //     await testVault.simulateYield();
    //     //     await controller.rebase();

    //     //     const treasuryUSDSTaBalT2 = await activatedToken.balanceOf(treasury.address);
    //     //     console.log("Treasury USDSTa bal: " + treasuryUSDSTaBalT2);

    //     //     // await controller.withdraw(owner.address, userUSDSTaBalT1.toString());
    //     //     // console.log("Treasury USDSTa bal: " + await activatedToken.balanceOf(treasury.address));
    //     // });

    //     it("Should convert USDST to DAI", async function () {

    //         const { controller, owner, activatedToken, unactivatedToken, testDAI, testVault, treasury } = await loadFixture(deployContracts);

    //         await controller.deposit(owner.address, "10000000000000000000000", false);

    //         const userUSDSTBalT0 = await unactivatedToken.balanceOf(owner.address);
    //         console.log("User USDST bal: " + userUSDSTBalT0);

    //         const treasuryUSDSTaBal = await activatedToken.balanceOf(treasury.address);
    //         console.log("Treasury USDSTa bal: " + treasuryUSDSTaBal);

    //         const vaultDAIBal = await testDAI.balanceOf(testVault.address);
    //         console.log("Test Vault DAI bal: " + vaultDAIBal);

    //         const treasuryBackingReserveT0 = await treasury.backingReserve(
    //             unactivatedToken.address,
    //             activatedToken.address
    //         );
    //         console.log(treasuryBackingReserveT0);

    //         await testVault.simulateYield();
    //         await controller.rebase();

    //         await controller.unactiveRedemption(userUSDSTBalT0.toString(), false);

    //         const userDAIBal = await testDAI.balanceOf(owner.address);
    //         console.log("User DAI bal: " + userDAIBal);

    //         const treasuryUSDSTaBalT1 = await activatedToken.balanceOf(treasury.address);
    //         console.log("Treasury USDSTa bal: " + treasuryUSDSTaBalT1);

    //         const treasuryBackingReserveT1 = await treasury.backingReserve(
    //             unactivatedToken.address,
    //             activatedToken.address
    //         );
    //         console.log(treasuryBackingReserveT1);

    //         const treasuryUSDSTaBalT2 = await activatedToken.balanceOf(treasury.address);
    //         console.log("Treasury USDSTa bal: " + treasuryUSDSTaBalT2);

    //         // await controller.withdraw(owner.address, userUSDSTaBalT1.toString());
    //         // console.log("Treasury USDSTa bal: " + await activatedToken.balanceOf(treasury.address));
    //     });
    // });

    // describe("Addresses should be set", async function () {

    //     it("Should set Controller for testDAI in SafeOps", async function () {

    //         const { testDAI, controller, safeOps } = await loadFixture(deployContracts);

    //         expect(await safeOps.getController(testDAI.address)).to.equal(controller.address);
    //     });

    //     it("Should set Controller for USDSTa in SafeOps", async function () {

    //         const { activatedToken, controller, safeOps } = await loadFixture(deployContracts);

    //         expect(await safeOps.getController(activatedToken.address)).to.equal(controller.address);
    //     });

    //     it("Should set SafeOps in SafeManager", async function () {

    //         const { safeOps, safeManager } = await loadFixture(deployContracts);

    //         expect(await safeManager.safeOperations()).to.equal(safeOps.address);
    //     });

    //     it("Should set SafeOps in Controller", async function () {

    //         const { safeOps, controller } = await loadFixture(deployContracts);

    //         expect(await controller.safeOperations()).to.equal(safeOps.address);
    //     });

    //     it("Should set SafeManager in Controller", async function () {

    //         const { safeManager, controller } = await loadFixture(deployContracts);

    //         expect(await controller.safeManager()).to.equal(safeManager.address);
    //     });
    // });

    // describe("Should open Safe", function () {

    //     it("Should open Safe with tDAI", async function () {

    //         const { owner, activatedToken, testDAI, safeManager, safeOps } = await loadFixture(deployContracts);

    //         await safeOps.openSafe(testDAI.address, "10000000000000000000000");

    //         const safeInitResponse = await safeManager.getSafeInit(owner.address, 0);
    //         console.log(safeInitResponse);

    //         expect(safeInitResponse[0]).to.equal(owner.address);
    //         expect(safeInitResponse[1]).to.equal(activatedToken.address);
    //         expect(safeInitResponse[2]).to.equal("0x0000000000000000000000000000000000000000");

    //         const safeBalResponse = await safeManager.getSafeVal(owner.address, 0);
    //         console.log(safeBalResponse);
    //         expect(safeBalResponse[0]).to.equal("10000000000000000000000");
    //         expect(safeBalResponse[2]).to.equal("10000000000000000000000");

    //         expect(await safeManager.getSafeStatus(owner.address, 0)).to.equal(1);
    //     });

    //     it("Should open Safe with USDSTa", async function () {

    //         const { owner, activatedToken, controller, safeManager, safeOps } = await loadFixture(deployContracts);

    //         await controller.deposit(owner.address, "10000000000000000000000", true);

    //         const userUSDSTaBal = await activatedToken.balanceOf(owner.address);
    //         console.log(userUSDSTaBal);

    //         await safeOps.openSafe(activatedToken.address, userUSDSTaBal.toString());

    //         const safeInitResponse = await safeManager.getSafeInit(owner.address, 0);
    //         console.log(safeInitResponse);

    //         expect(safeInitResponse[0]).to.equal(owner.address);
    //         expect(safeInitResponse[1]).to.equal(activatedToken.address);
    //         expect(safeInitResponse[2]).to.equal("0x0000000000000000000000000000000000000000");

    //         const safeBalResponse = await safeManager.getSafeVal(owner.address, 0);
    //         console.log(safeBalResponse);
    //         expect(safeBalResponse[0]).to.equal(userUSDSTaBal.toString());
    //         // expect(safeBalResponse[2]).to.equal("10000000000000000000000");

    //         expect(await safeManager.getSafeStatus(owner.address, 0)).to.equal(1);
    //     });
    // });

    // describe("Safe deposit", function () {

    //     it("Should deposit to Safe", async function () {
            
    //         const { owner, activatedToken, testDAI, testVault, safeManager, safeOps, activePool, controller } = await loadFixture(deployContracts);

    //         await safeOps.openSafe(testDAI.address, "5000000000000000000000");

    //         // await testVault.simulateYield();
    //         // await controller.rebase();

    //         console.log(await safeManager.getSafeVal(owner.address, 0));

    //         await safeOps.depositToSafe(testDAI.address, 0, "5000000000000000000000");

    //         console.log(await safeManager.getSafeVal(owner.address, 0));

    //         await testVault.simulateYield();
    //         await controller.rebase();

    //         const activeTokens = await activePool.previewRedeem("10000000000000000000000");
    //         console.log("activeTokens in user's Safe: " + activeTokens);

    //         await safeOps.withdrawTokens(true, 0, "10000000000000000000000");

    //         console.log("Val: " + await safeManager.getSafeVal(owner.address, 0));
    //         console.log("Status: " + await safeManager.getSafeStatus(owner.address, 0));

    //         console.log("User USDSTa bal: " + await activatedToken.balanceOf(owner.address));
    //         console.log("AP USDSTa bal: " + await activatedToken.balanceOf(activePool.address));

            // const safeMngrBalance = await activatedToken.balanceOf(safeManager.address);
            // console.log(safeMngrBalance);
            
            // const withdrawTokenResponse = await safeOps.withdrawTokens(false, 0, "10000000000000000000000");
            // console.log("Withdraw Response: " + withdrawTokenResponse);

            // const ownerBal = await testDAI.balanceOf(owner.address);
            // console.log(ownerBal);
            // expect(ownerBal).to.be.greaterThan("10000000000000000000000");
        // });

        // it("Should withdraw activeToken + yield", async function () {

        //     // await hre.network.provider.send("hardhat_reset");
            
        //     const { owner, activatedToken, testDAI, testVault, safeManager, safeOps, controller } = await loadFixture(deployContracts);
    
        //     // Deposit inputToken
        //     await safeOps.openSafe(testDAI.address, "10000000000000000000000");
    
        //     await testVault.simulateYield();
    
        //     const rebaseResponse = await controller.rebase();
        //     console.log(rebaseResponse);
    
        //     console.log(await safeManager.getSafeVal(owner.address, 0));
    
        //     const safeMngrBalance = await activatedToken.balanceOf(safeManager.address);
        //     console.log(safeMngrBalance);
            
        //     const withdrawTokenResponse = await safeOps.withdrawTokens(true, 0, "10000000000000000000000");
        //     console.log("Withdraw Response: " + withdrawTokenResponse);
    
        //     const ownerBal = await activatedToken.balanceOf(owner.address);
        //     console.log("Owner bal: " + ownerBal);
        //     // expect(ownerBal).to.be.greaterThan("10000000000000000000000");
    
        //     console.log("Safe val: " + await safeManager.getSafeVal(owner.address, 0));
        // });
    // });
});