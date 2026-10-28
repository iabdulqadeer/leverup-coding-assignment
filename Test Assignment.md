# Smart Contract Engineer — Coding Assignment

## Overview

This is a **2-hour smart contract debugging and security exercise** prepared for LeverUp, a decentralized perpetual trading protocol on Monad.

The repository contains a small perpetual-position engine with an oracle and an in-memory mock collateral token. The code is intentionally compact and appears straightforward, but it contains several correctness and security issues.

Your task is to review the contracts, identify the important bugs, and implement appropriate fixes.

You are being evaluated primarily on **reasoning, security awareness, correctness, and the quality of the patch**, not on how many lines you change.

> **You do not need to deploy this project or connect to a live blockchain.**
> You may use static analysis, compilation, tests, or other local tooling if available, but the assignment is designed to be solvable by reviewing the source code.

---

## Time limit

**2 hours maximum.**

The timer begins with your `START` commit and ends with your `DONE` commit.

Please do not make the `START` commit before you are ready to begin.

### Required timing procedure

First create your own branch:

```bash
git checkout -b candidate/<your-name>
```

Then immediately create the start commit:

```bash
git commit --allow-empty -m "START: coding assignment"
```

When you have finished your implementation and final review, create the final commit:

```bash
git add .
git commit -m "DONE: coding assignment"
```

Please do not amend or rewrite the `START` or `DONE` commits. We will use the Git commit timestamps to verify the elapsed time.

If you finish early, submit early. You do not need to use the entire two hours.

---

## Task

Review the Solidity contracts in the repository and fix the bugs you find.

At minimum, review the following areas:

1. **Position accounting**
   - Long and short PnL
   - Margin/equity calculations
   - Closing positions

2. **Liquidation**
   - Whether an unhealthy position can remain open
   - Whether a healthy position can be liquidated
   - Liquidation reward / remaining collateral

3. **Oracle / price safety**
   - Whether the price used by the protocol is safe to consume
   - Stale or invalid price data
   - Decimal handling

4. **Fees and leverage**
   - Maximum leverage
   - Fee calculation
   - Whether fee and margin accounting remain internally consistent

5. **Access control and state integrity**
   - Who is allowed to update protocol-critical state
   - Whether a user can manipulate another user's position
   - Whether state can be left inconsistent after a failed operation

6. **External calls / token handling**
   - ERC-20 return values
   - Reentrancy or interaction-order risks
   - Transfers made before or after state changes

You should prioritize issues that could cause **loss of funds, incorrect settlement, unauthorized state changes, or incorrect liquidation**.

---

## Expected result

Make the smallest reasonable production-quality patch.

You should:

- Fix the underlying problems rather than merely hiding symptoms.
- Preserve the intended public API where practical.
- Add or improve comments only where they clarify important invariants.
- Avoid unrelated refactoring.
- Keep the implementation understandable and maintainable.

You may add tests if you want, but **tests are optional** for this assignment. If you add tests, keep them focused on the bugs you fixed.

---

## Important assumptions

For the purpose of this exercise:

- The collateral token uses **6 decimals**.
- The oracle price uses **8 decimals**.
- Position size/notional is represented in collateral-token units.
- The protocol supports leverage from **1x through 1001x**.
- The intended maintenance margin is **0.5% of notional**.
- The intended trading fee is **0.05% of notional**.
- Oracle prices are expected to be positive and reasonably fresh.
- Only the position owner should be able to open/close their own position.
- Liquidation is intended to be permissionless, but only when the position is genuinely below maintenance requirements.
- The mock token and oracle are simplified stand-ins for external protocol components.

You should use these assumptions when deciding what the correct behavior should be.

---

## Deliverables

Your final branch should contain:

1. The fixed Solidity source code.
2. Any focused tests you choose to add.
3. The final `DONE: coding assignment` commit.

Do **not** include generated build artifacts, dependency directories, private keys, or unrelated files.

---

## What we evaluate

We will review:

- **Security:** Can an attacker exploit the contract or manipulate protocol-critical state?
- **Financial correctness:** Are PnL, margin, fees, leverage, and liquidation handled correctly?
- **Oracle safety:** Are unsafe/stale/invalid prices rejected?
- **Access control:** Are privileged operations properly restricted?
- **State consistency:** Can partial operations leave incorrect accounting?
- **Code quality:** Is the fix clear, minimal, and maintainable?
- **Prioritization:** Did you focus on high-impact issues within the time limit?
- **Git discipline:** Did you follow the required `START` / `DONE` timing process?

We do **not** expect a large rewrite. A concise, well-reasoned security patch is preferable to unnecessary architectural changes.

---

## Suggested workflow

A practical workflow is:

```bash
git checkout -b candidate/<your-name>
git commit --allow-empty -m "START: coding assignment"

# Review the contracts
# Identify and fix the highest-impact issues
# Optionally add focused tests

git diff
git status

git add .
git commit -m "DONE: coding assignment"
```

You are free to use your preferred Solidity tooling and static-analysis tools if available.

Good luck.
