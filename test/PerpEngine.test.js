const assert = require("node:assert/strict");
const { ethers, network } = require("hardhat");

const USDC = 10n ** 6n;
const PRICE = 2000n * 10n ** 8n;
const MARGIN = 1000n * USDC;

async function revertsWith(promise, contract, errorName) {
  try {
    await promise;
  } catch (err) {
    const data = err.data ?? err.error?.data;
    const expected = contract.interface.getError(errorName).selector;
    if (typeof data === "string" && data.startsWith(expected)) return;
    assert.fail(`expected ${errorName}, got: ${err.message}`);
  }
  assert.fail(`expected ${errorName}, but the call succeeded`);
}

async function increaseTime(seconds) {
  await network.provider.send("evm_increaseTime", [seconds]);
  await network.provider.send("evm_mine");
}

describe("LeverUpPerpEngine", () => {
  let deployer, trader, liquidator, otherTrader, stranger;
  let usdc, oracle, engine;

  beforeEach(async () => {
    [deployer, trader, liquidator, otherTrader, stranger] = await ethers.getSigners();

    usdc = await (await ethers.getContractFactory("MockUSDC")).deploy();
    oracle = await (await ethers.getContractFactory("MockOracle")).deploy(PRICE);
    engine = await (await ethers.getContractFactory("LeverUpPerpEngine")).deploy(
      await usdc.getAddress(),
      await oracle.getAddress()
    );

    for (const account of [trader, otherTrader]) {
      await usdc.mint(account.address, 1_000_000n * USDC);
      await usdc.connect(account).approve(await engine.getAddress(), ethers.MaxUint256);
    }
  });

  describe("oracle", () => {
    it("rejects price updates from non-owners", async () => {
      await revertsWith(oracle.connect(stranger).setPrice(1n), oracle, "NotOwner");
      await revertsWith(oracle.connect(stranger).setPriceAndTimestamp(1n, 1n), oracle, "NotOwner");
    });

    it("lets the owner update the price", async () => {
      await oracle.setPrice(PRICE + 1n);
      assert.equal((await oracle.getPrice())[0], PRICE + 1n);
    });

    it("rejects a zero price", async () => {
      await oracle.setPrice(0n);
      await revertsWith(engine.connect(trader).openPosition(MARGIN, 10n, true), engine, "InvalidPrice");
    });

    it("rejects stale prices when opening, closing, and liquidating", async () => {
      await engine.connect(trader).openPosition(MARGIN, 10n, true);
      await increaseTime(61);

      await revertsWith(engine.connect(otherTrader).openPosition(MARGIN, 10n, true), engine, "StalePrice");
      await revertsWith(engine.connect(trader).closePosition(), engine, "StalePrice");
      await revertsWith(engine.connect(liquidator).liquidate(trader.address), engine, "StalePrice");
    });

    it("accepts a price exactly at the maximum age", async () => {
      await engine.connect(trader).openPosition(MARGIN, 10n, true);
      const { timestamp } = await ethers.provider.getBlock("latest");
      await oracle.setPriceAndTimestamp(PRICE, BigInt(timestamp) + 1n);
      await network.provider.send("evm_setNextBlockTimestamp", [timestamp + 61]);
      await engine.connect(trader).closePosition();
    });

    it("rejects future-dated prices", async () => {
      const { timestamp } = await ethers.provider.getBlock("latest");
      await oracle.setPriceAndTimestamp(PRICE, BigInt(timestamp) + 3600n);
      await revertsWith(engine.connect(trader).openPosition(MARGIN, 10n, true), engine, "StalePrice");
    });
  });

  describe("settlement", () => {
    it("pays long and short PnL in the correct direction", async () => {
      await engine.connect(trader).openPosition(MARGIN, 10n, true);
      await engine.connect(otherTrader).openPosition(MARGIN, 10n, false);
      const fee = 5n * USDC;
      await oracle.setPrice((PRICE * 101n) / 100n); // +1% on a 10,000 USDC notional

      const longBefore = await usdc.balanceOf(trader.address);
      await engine.connect(trader).closePosition();
      assert.equal((await usdc.balanceOf(trader.address)) - longBefore, MARGIN - fee + 100n * USDC);

      const shortBefore = await usdc.balanceOf(otherTrader.address);
      await engine.connect(otherTrader).closePosition();
      assert.equal((await usdc.balanceOf(otherTrader.address)) - shortBefore, MARGIN - fee - 100n * USDC);
    });

    it("rejects a second open and a close with no position", async () => {
      await engine.connect(trader).openPosition(MARGIN, 10n, true);
      await revertsWith(engine.connect(trader).openPosition(MARGIN, 10n, true), engine, "PositionAlreadyOpen");
      await revertsWith(engine.connect(stranger).closePosition(), engine, "NoPosition");
    });
  });

  describe("leverage", () => {
    it("accepts the highest leverage that is healthy at open", async () => {
      await engine.connect(trader).openPosition(MARGIN, 181n, true);
      await revertsWith(engine.connect(liquidator).liquidate(trader.address), engine, "NotLiquidatable");
    });

    it("rejects leverage that would be liquidatable at open", async () => {
      await revertsWith(engine.connect(trader).openPosition(MARGIN, 182n, true), engine, "InvalidLeverage");
      await revertsWith(engine.connect(trader).openPosition(MARGIN, 1001n, true), engine, "InvalidLeverage");
    });

    it("rejects zero leverage and leverage above the maximum", async () => {
      await revertsWith(engine.connect(trader).openPosition(MARGIN, 0n, true), engine, "InvalidLeverage");
      await revertsWith(engine.connect(trader).openPosition(MARGIN, 1002n, true), engine, "InvalidLeverage");
    });

    it("rejects a position whose margin is consumed by rounding", async () => {
      await revertsWith(engine.connect(trader).openPosition(1n, 1n, true), engine, "InvalidLeverage");
    });
  });

  describe("fees", () => {
    it("records the fee and stores margin net of it", async () => {
      await engine.connect(trader).openPosition(MARGIN, 10n, true);
      const fee = 5n * USDC;
      assert.equal(await engine.accruedFees(), fee);
      assert.equal((await engine.positions(trader.address)).margin, MARGIN - fee);
    });

    it("rounds the fee up so small positions still pay", async () => {
      await engine.connect(trader).openPosition(100n, 1n, true);
      assert.equal(await engine.accruedFees(), 1n);
    });

    it("emits the margin that was actually stored", async () => {
      const tx = await engine.connect(trader).openPosition(MARGIN, 10n, true);
      const receipt = await tx.wait();
      const log = engine.interface.parseLog(receipt.logs.at(-1));
      assert.equal(log.args.margin, MARGIN - 5n * USDC);
    });

    it("lets only the owner withdraw fees, and only once", async () => {
      await engine.connect(trader).openPosition(MARGIN, 10n, true);
      await revertsWith(engine.connect(stranger).withdrawFees(stranger.address), engine, "NotOwner");

      await engine.withdrawFees(deployer.address);
      assert.equal(await usdc.balanceOf(deployer.address), 5n * USDC);
      assert.equal(await engine.accruedFees(), 0n);

      await engine.withdrawFees(deployer.address);
      assert.equal(await usdc.balanceOf(deployer.address), 5n * USDC);
    });
  });

  describe("liquidation", () => {
    // 100x long on 1,000 USDC: notional 100,000, fee 50, margin 950, maintenance 500.
    // Equity reaches maintenance after a 450 USDC loss, which is a 0.45% price drop.
    const atMaintenance = (PRICE * 9955n) / 10000n;
    const belowMaintenance = (PRICE * 9950n) / 10000n; // loss 500, equity 450
    const underwater = (PRICE * 9900n) / 10000n; // loss 1,000, equity 0

    beforeEach(async () => {
      await engine.connect(trader).openPosition(MARGIN, 100n, true);
    });

    it("rejects liquidating a healthy position", async () => {
      await revertsWith(engine.connect(liquidator).liquidate(trader.address), engine, "NotLiquidatable");
    });

    it("rejects liquidation exactly at maintenance", async () => {
      await oracle.setPrice(atMaintenance);
      await revertsWith(engine.connect(liquidator).liquidate(trader.address), engine, "NotLiquidatable");
    });

    it("pays the reward and returns remaining equity to the trader", async () => {
      await oracle.setPrice(belowMaintenance);
      const traderBefore = await usdc.balanceOf(trader.address);

      await engine.connect(liquidator).liquidate(trader.address);

      const reward = (950n * USDC) / 20n; // 47.5
      assert.equal(await usdc.balanceOf(liquidator.address), reward);
      assert.equal((await usdc.balanceOf(trader.address)) - traderBefore, 450n * USDC - reward);
      assert.equal((await engine.positions(trader.address)).notional, 0n);
    });

    it("caps the reward at equity so an underwater position pays nothing", async () => {
      await oracle.setPrice(underwater);
      const traderBefore = await usdc.balanceOf(trader.address);

      await engine.connect(liquidator).liquidate(trader.address);

      assert.equal(await usdc.balanceOf(liquidator.address), 0n);
      assert.equal(await usdc.balanceOf(trader.address), traderBefore);
      assert.equal((await engine.positions(trader.address)).notional, 0n);
    });

    it("gives no gain from self-liquidating an underwater position", async () => {
      await oracle.setPrice(underwater);
      const before = await usdc.balanceOf(trader.address);
      await engine.connect(trader).liquidate(trader.address);
      assert.equal(await usdc.balanceOf(trader.address), before);
    });

    it("gives the same total from self-liquidating as from closing", async () => {
      await oracle.setPrice(belowMaintenance);
      const before = await usdc.balanceOf(trader.address);
      await engine.connect(trader).liquidate(trader.address);
      assert.equal((await usdc.balanceOf(trader.address)) - before, 450n * USDC);
    });
  });

  describe("token handling", () => {
    let token, tokenEngine;

    beforeEach(async () => {
      token = await (await ethers.getContractFactory("TestToken")).deploy();
      tokenEngine = await (await ethers.getContractFactory("LeverUpPerpEngine")).deploy(
        await token.getAddress(),
        await oracle.getAddress()
      );
      await token.setEngine(await tokenEngine.getAddress());
      await token.mint(trader.address, MARGIN);
    });

    it("supports tokens that return no value", async () => {
      await tokenEngine.connect(trader).openPosition(MARGIN, 10n, true);
      await tokenEngine.connect(trader).closePosition();
      assert.equal(await token.balanceOf(trader.address), MARGIN - 5n * USDC);
    });

    it("writes the position before pulling collateral", async () => {
      await tokenEngine.connect(trader).openPosition(MARGIN, 10n, true);
      assert.equal(await token.notionalSeenDuringTransfer(), 10n * MARGIN);
    });

    it("leaves no position behind when the collateral transfer fails", async () => {
      await revertsWith(
        engine.connect(stranger).openPosition(MARGIN, 10n, true),
        engine,
        "TransferFailed"
      );
      assert.equal((await engine.positions(stranger.address)).notional, 0n);
    });

    it("rejects a zero token or oracle address", async () => {
      const factory = await ethers.getContractFactory("LeverUpPerpEngine");
      await revertsWith(factory.deploy(ethers.ZeroAddress, await oracle.getAddress()), engine, "InvalidAddress");
      await revertsWith(factory.deploy(await usdc.getAddress(), ethers.ZeroAddress), engine, "InvalidAddress");
    });
  });
});
