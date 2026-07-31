# 1MEME-Spark

Spark lets anyone deploy a meme token and seed permanent one-sided V3 liquidity in a single
transaction on any registered DEX. Liquidity is locked forever in `SparkLocker`; only accrued
swap fees can be claimed. See [spark/SPARK.md](spark/SPARK.md) for full architecture, launch
flow, and function reference.

## Contracts

| File | Contract | Role |
|------|----------|------|
| `spark/SparkToken.sol` | `SparkToken` | ERC-20 + EIP-2612 implementation used as the EIP-1167 clone template |
| `spark/SparkLauncher.sol` | `SparkLauncher` | v3-style launcher — clones token, creates a pool, seeds one-sided liquidity |
| `spark/SparkLocker.sol` | `SparkLocker` | Permanent LP-NFT vault for `SparkLauncher`; distributes swap fees to creator and platform |
| `spark-v2/SparkLauncherV2.sol` | `SparkLauncherV2` | BNB-only meme launcher for Uniswap v4 and PancakeSwap Infinity (CL pools) on BNB Smart Chain |
| `spark-v2/hooks/SparkHookV4.sol` | `SparkHookV4` | Optional v4 hook — anti-sandwich, max-buy/max-wallet, and a 2% sell-side swap fee, paid entirely in native BNB |
| `spark-v2/hooks/SparkHookInfinity.sol` | `SparkHookInfinity` | Same protections as `SparkHookV4`, for PancakeSwap Infinity CL pools |
| `spark-v2/SparkBurner.sol` | `SparkBurner` | Receives fees for any token launched with `feeWallet_ = address(0)`; anyone can call `burnV4`/`burnInfinity` to swap 95% of the accrued native BNB into the token and burn it, paying the caller the other 5% in native BNB |

`SparkLauncherV2` only ever pairs against native BNB — no other quote token is supported. An
earlier version supported arbitrary quote tokens with a multihop instant buy, but testing against
real BSC mainnet liquidity found that route fragile in ways that don't fail loudly: PancakeSwap
Infinity had no BNB/stablecoin liquidity at any common tier, and Uniswap v4's placeholder tier
looked identical on-chain (initialized, callable, no revert) while holding almost no depth,
delivering a tiny fraction of expected output with no slippage protection to catch it. Going
BNB-only removes that class of risk: native BNB is the one pool every DEX guarantees can exist, so
the contract never has to guess which fee tier or currency form actually has depth.

`SparkLauncherV2.tokenHook(token)` records the exact hook a token was launched with, captured once
at launch time — use this rather than `dexes(positionManager).hook`, which reflects the DEX's
*current* hook and can drift out of sync for older tokens if the owner later calls `addDex()` to
rotate that DEX onto a different hook.

A hook is mandatory for every launch — `launch()` reverts (`HookRequired`) rather than falling
back to a pool-level fee if a DEX's registered hook is `address(0)`. Every pool carries no
pool-level (AMM) fee at all (`fee: 0`); instead `SparkHookV4`/`SparkHookInfinity` charge their own
flat 2% fee, taken only on exact-input sells and always in native BNB, never in the token, so
creators and the platform only ever receive BNB, never SparkToken. Buys and exact-output sells are
never charged.

Every `SparkLauncherV2` token clone address must end in `0x1111` (enforced on-chain) — mine a
valid `vanitySalt_` with [`spark-v2/saltminer/`](spark-v2/saltminer/index.html) before calling
`launch()`. `SparkHookV4` additionally needs to be deployed via CREATE2 to an address whose low 14
bits equal `SparkHookV4.REQUIRED_PERMISSIONS` (`0xC4`) — Uniswap v4 reads hook permissions from the
deployed address itself, unlike Infinity, which reads `SparkHookInfinity.getHooksRegistrationBitmap()`
instead and can be deployed anywhere.

If a launched token's original team goes dark, `SparkLocker`/`SparkHookV4`/`SparkHookInfinity` all
support community takeover: anyone can `applyForCTO(...)` (paying a non-refundable anti-spam fee,
`ctoFee`, default 0.1 BNB) to propose reassigning the token's fee wallet (v3) or pool creator (v2);
only the contract owner can `approveCTO`/`rejectCTO` to actually act on it. See
[spark/SPARK.md](spark/SPARK.md#community-takeover-cto) for the v3 details.

`launch()` on `SparkLauncherV2` treats a `feeWallet_` of `address(0)` as "route this token's fees
to the burner" rather than defaulting to the caller — `SparkLauncherV2.burner` must be set
(`setBurner`, owner-only) or the launch reverts (`BurnerRequired`). `SparkHookV4.claimFees`/
`SparkHookInfinity.claimFees` are permissionless — anyone can trigger a payout, which always lands
on the pool's registered `creator` (the burner, in this case) and `platformWallet` regardless of
caller. `SparkBurner.burnV4`/`burnInfinity` then claims those fees, swaps 95% of the claimed native
BNB into the token and sends the full result to `0x…dEaD`, then pays the caller the remaining 5% in
native BNB — never in the token — as an incentive to keep calling it.

## Build

```bash
npm install
npm run compile          # node compile.js
npm run compile:verbose  # include compiler warnings
```

Compiles with `solc` (`viaIR: true`, optimizer 200 runs) and writes ABI/bytecode artifacts to `out/`.
