import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Controller__factory } from "../typechain-types";

const hre = require("hardhat");

describe("Safe", function () {

    async function deployContracts() {

        const [owner] = await ethers.getSigners();
        // const MAX_INT = (2^256 - 1).toString();

        const ActivatedToken = await ethers.getContractFactory("ActivatedToken");
        const UnactivatedToken = await ethers.getContractFactory("UnactivatedToken");
        const TestDAI = await ethers.getContractFactory("TestDAI");
        const TestVault = await ethers.getContractFactory("TestVault");
        const Controller = await ethers.getContractFactory("Controller");
        const SafeManager = await ethers.getContractFactory("SafeManager");
        const SafeOps = await ethers.getContractFactory("SafeOperations");
        const activatedToken = await ActivatedToken.deploy("Stoa Activated Dollar", "USDSTa");
        const unactivatedToken = await UnactivatedToken.deploy("Stoa Dollar", "USDST");
        const testDAI = await TestDAI.deploy();
        const testVault = await TestVault.deploy(testDAI.address, testDAI.address, "Test yvDAI", "tyvDAI");
        const controller = await Controller.deploy(testVault.address, testDAI.address, activatedToken.address, unactivatedToken.address);
        const safeManager = await SafeManager.deploy();
        const safeOps = await SafeOps.deploy(safeManager.address);

        await controller.rebaseOptIn(activatedToken.address);
        await safeManager.rebaseOptIn(activatedToken.address);

        await safeOps.setController(testDAI.address, controller.address);
        await safeOps.setController(activatedToken.address, controller.address);
        await safeManager.setSafeOps(safeOps.address);
        await controller.setSafeOps(safeOps.address);
        await controller.setSafeManager(safeManager.address);

        await safeManager.approveToken(activatedToken.address, safeOps.address);
        await testDAI.approve(testVault.address, "1000000000000000000000000");

        return { 
            owner, activatedToken, unactivatedToken, testDAI, testVault, controller, safeManager, safeOps
        };
    }
    
    // describe("Rebase Opt-in", function () {

    //     it("Controller should opt-in", async function () {

    //         const { activatedToken, controller } = await loadFixture(deployContracts);

    //         expect(await activatedToken.rebaseState(controller.address)).to.equal(2);
    //     });

    //     it("SafeManager should opt-in", async function () {

    //         const { activatedToken, safeManager } = await loadFixture(deployContracts);

    //         expect(await activatedToken.rebaseState(safeManager.address)).to.equal(2);
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

    //         const { owner, activatedToken, testDAI, testVault, safeManager, safeOps } = await loadFixture(deployContracts);

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
    // });

    describe("Safe withdrawal", function () {

        // it("Should withdraw inputToken + yield", async function () {

        //     // await hre.network.provider.send("hardhat_reset");
            
        //     const { owner, activatedToken, testDAI, testVault, safeManager, safeOps, controller } = await loadFixture(deployContracts);

        //     await safeOps.openSafe(testDAI.address, "10000000000000000000000");

        //     await testVault.simulateYield();

        //     const rebaseResponse = await controller.rebase();
        //     // console.log(rebaseResponse);

        //     console.log(await safeManager.getSafeVal(owner.address, 0));

        //     const safeMngrBalance = await activatedToken.balanceOf(safeManager.address);
        //     console.log(safeMngrBalance);
            
        //     const withdrawTokenResponse = await safeOps.withdrawTokens(false, 0, "10000000000000000000000");
        //     console.log("Withdraw Response: " + withdrawTokenResponse);

        //     const ownerBal = await testDAI.balanceOf(owner.address);
        //     console.log(ownerBal);
        //     expect(ownerBal).to.be.greaterThan("10000000000000000000000");
        // });

        it("Should withdraw activeToken + yield", async function () {

            // await hre.network.provider.send("hardhat_reset");
            
            const { owner, activatedToken, testDAI, testVault, safeManager, safeOps, controller } = await loadFixture(deployContracts);
    
            // Deposit inputToken
            await safeOps.openSafe(testDAI.address, "10000000000000000000000");
    
            await testVault.simulateYield();
    
            const rebaseResponse = await controller.rebase();
            console.log(rebaseResponse);
    
            console.log(await safeManager.getSafeVal(owner.address, 0));
    
            const safeMngrBalance = await activatedToken.balanceOf(safeManager.address);
            console.log(safeMngrBalance);
            
            const withdrawTokenResponse = await safeOps.withdrawTokens(true, 0, "10000000000000000000000");
            console.log("Withdraw Response: " + withdrawTokenResponse);
    
            const ownerBal = await activatedToken.balanceOf(owner.address);
            console.log("Owner bal: " + ownerBal);
            // expect(ownerBal).to.be.greaterThan("10000000000000000000000");
    
            console.log("Safe val: " + await safeManager.getSafeVal(owner.address, 0));
        });
    });
});