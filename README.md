# 1MEME-Spark

Spark lets anyone deploy a meme token and seed permanent one-sided liquidity in a single
transaction on any registered DEX. Liquidity is locked forever in `SparkLocker`; only accrued
swap fees can be claimed. Three independent, UUPS-upgradeable launcher families exist — including
SparkCF, a crowdfund launcher where a token only launches once a public raise actually funds its
liquidity — see [Deployment.md](Deployment.md) for live addresses and deploy history.

## Contracts

| File | Contract | Role |
|------|----------|------|
| `spark/SparkToken.sol` | `SparkToken` | ERC-20 + EIP-2612 implementation used as the EIP-1167 clone template |
| `spark/SparkLauncherUpgradeable.sol` | `SparkLauncher` | UUPS-upgradeable — plain Uniswap V3 / PancakeSwap V3 launcher, plus the shared routing engine below |
| `spark/SparkLocker.sol` | `SparkLocker` | Permanent LP-NFT vault for `SparkLauncher`; distributes swap fees to creator and platform |
| `spark-go/SparkGoLauncher.sol` | `SparkGoLauncher` | Upgradeable, currency-general launcher for Uniswap v4 / PancakeSwap Infinity (singleton pools) |
| `spark-go/hooks/SparkGoHookV4.sol` | `SparkGoHookV4` | v4 hook — anti-sandwich (same-block re-entry block), and a 2% sell-side swap fee, paid in whichever currency the pool is quoted against |
| `spark-go/hooks/SparkGoHookInfinity.sol` | `SparkGoHookInfinity` | Same protections as `SparkGoHookV4`, for PancakeSwap Infinity CL pools |
| `spark-go/SparkGoBurner.sol` | `SparkGoBurner` | Receives fees for any token launched with `feeWallet_ = address(0)`; anyone can call `burnV4`/`burnInfinity` to swap 95% of the accrued fees into the token and burn it, paying the caller the other 5% |
| `common/SparkRouting.sol` | `SparkRouting` (abstract) | Shared bounded-fallback instant-buy routing engine — an owner-configured, ordered list of concrete routes per quote token, inherited by both launchers |
| `spark-cf/SparkCFToken.sol` | `SparkCFToken` | ERC-20 + EIP-2612 clone template for SparkCF — no antibot, no platform cut. A per-token transfer tax (creator-configured, capped at `MAX_TAX_BPS`) is skimmed only on trades against the token's own AMM pair and paid entirely to the creator's `taxWallet`; wallet-to-wallet transfers are always tax-free |
| `spark-cf/SparkCFLauncher.sol` | `SparkCFLauncher` | UUPS-upgradeable — permissionless crowdfund launcher. Anyone opens a campaign targeting a fixed USD goal (TWAP-priced into native wei at creation), fundable only in native currency, running for a fixed duration from an instant-live or scheduled start time. A campaign clearing its goal deploys its token and pairs 100% of the raised funds (swapped first into the creator's chosen DEX quote asset if it isn't native, via the inherited `SparkRouting`) as real liquidity — two-sided Uniswap V3/PancakeSwap V3 registered with its own dedicated `SparkLocker` for tax-free tokens, or V2-style with the LP burned for taxed tokens — splitting supply pro-rata between contributors (claimable) and the LP. A campaign that misses its goal unlocks full refunds instead |
| `distributor/MultiSender.sol` | `MultiSender` | Independent, protocol-agnostic batch sender — no relation to any Spark launcher. Permissionless and fully stateless: `disperseEther`/`disperseEtherEqual` fan out native value, `disperseToken`/`disperseTokenEqual` pull ERC20 directly from the caller per recipient (`Equal` variants take one amount for every recipient instead of a matching array) |
| `distributor/MerkleDistributor.sol` | `MerkleDistributor` | Independent, UUPS-upgradeable claim-based distributor. Anyone can open a funded campaign (native or ERC20) per Merkle root via `createCampaign`, paying a flat native `campaignFee` (funds the platform's indexing/API work needed to surface other people's drops) — recipients `claim` with a proof (funds always go to the committed `account`, so anyone can pay gas on their behalf); only that campaign's own `creator` can `sweep` its unclaimed remainder after its deadline. One contract can host many independent campaigns — each tracks its own `remaining` balance so accounting never mixes |

Both launchers support arbitrary quote tokens, not just native BNB. `common/SparkRouting.sol`
handles instant-buy as an owner-configured, ordered fallback list of real routes per quote token
(covering Uniswap/PancakeSwap V2, V3, v4, and Infinity), tried in turn with real
`minQuoteOut`/`minTokensOut` slippage floors. A single logical route can also chain hops across
*different* DEXs (`Route.routers[]`, one router per hop) — useful when a quote token's cheapest
native leg lives on one DEX but its only real liquidity for the launched token sits on another.

`SparkGoLauncher.tokenHook(token)` records the exact hook a token was launched with, captured once
at launch time — use this rather than `dexes(positionManager).hook`, which reflects the DEX's
*current* hook and can drift out of sync for older tokens if the owner later calls `addDex()` to
rotate that DEX onto a different hook.

A hook is mandatory for every `SparkGoLauncher` launch — `launch()` reverts (`HookRequired`)
rather than falling back to a pool-level fee if a DEX's registered hook is `address(0)`. Every
pool carries no pool-level (AMM) fee at all (`fee: 0`); instead `SparkGoHookV4`/
`SparkGoHookInfinity` charge their own flat 2% fee, taken only on exact-input sells and always in
the pool's quote currency, never in the launched token, so creators and the platform only ever
receive the quote currency. Buys and exact-output sells are never charged.

Every launched token's clone address must end in `0x1111` (enforced on-chain, `VANITY_SUFFIX`) —
mine a valid `vanitySalt_` with [`spark-go/saltminer/`](spark-go/saltminer/index.html) before
calling `launch()`; the tool works for either launcher, just point it at the right
launcher/token-impl addresses. `SparkGoHookV4` additionally needs to be deployed via CREATE2 to an
address whose low 14 bits equal `SparkGoHookV4.REQUIRED_PERMISSIONS` (`0xC4`) — Uniswap v4 reads
hook permissions from the deployed address itself, unlike Infinity, which reads
`SparkGoHookInfinity.getHooksRegistrationBitmap()` instead and can be deployed anywhere.

If a launched token's original team goes dark, `SparkLocker`/`SparkGoHookV4`/`SparkGoHookInfinity`
all support community takeover: anyone can `applyForCTO(...)` (paying a non-refundable anti-spam
fee, `ctoFee`, default 0.1 BNB) to propose reassigning the token's fee wallet (`SparkLauncher`) or
pool creator (`SparkGoLauncher`); only the contract owner can `approveCTO`/`rejectCTO` to actually
act on it.

`launch()` on `SparkGoLauncher` treats a `feeWallet_` of `address(0)` as "route this token's fees
to the burner" rather than defaulting to the caller — `SparkGoLauncher.burner` must be set
(`setBurner`, owner-only) or the launch reverts (`BurnerRequired`). `SparkGoHookV4.claimFees`/
`SparkGoHookInfinity.claimFees` are permissionless — anyone can trigger a payout, which always
lands on the pool's registered `creator` (the burner, in this case) and `platformWallet`
regardless of caller. `SparkGoBurner.burnV4`/`burnInfinity` then claims those fees, swaps 95% of
the claimed quote currency into the token and sends the full result to `0x…dEaD`, then pays the
caller the remaining 5% — as an incentive to keep calling it.

**SparkCF** is a third, independent launcher family — a crowdfund rather than an instant launch.
Its funding goal is a fixed USD target (owner-configurable, defaults to $3000, no minimum floor)
priced into native wei via TWAP at `createCampaign()` time, averaging a Uniswap-v3-style pool (read
statelessly via `observe()`) and a
Uniswap-v2-style pair (which needs its own accumulator state, updated as a side effect of normal
`createCampaign()`/`contribute()` calls — no separate maintenance function) if both are configured.
Contributions are native-only; the goal is a soft floor, not a cap, so overshoot dilutes contributor
allocations rather than being rejected — every contributor's tokens-per-BNB ratio is identical
regardless of when they contributed, and the launch pool's price (using the LP-seeded portion of
supply as circulating, the standard convention for a freshly launched token) always equals exactly
what was raised, whatever that ends up being — `finalize()` only triggers once the campaign's fixed
duration has fully elapsed, never early on hitting the goal. `SparkCFLauncher` doesn't
share `SparkLauncher`/`SparkGoLauncher`'s locker or token implementation — it gets its own
dedicated third `SparkLocker` instance (used only by tax-free campaigns, which seed real two-sided
Uniswap V3/PancakeSwap V3 liquidity) and its own `SparkCFToken` clone template (taxed campaigns
seed V2-style liquidity instead, with the LP burned in the same call, since V3's concentrated-
liquidity accounting is well known to break under fee-on-transfer tokens).

## Build

```bash
npm install
npm run compile          # node compile.js
npm run compile:verbose  # include compiler warnings
```

Compiles with `solc` (`viaIR: true`, optimizer 200 runs) and writes ABI/bytecode artifacts to
`out/`. Deploy scripts and the fork-test suite live in [`deploy/`](deploy/), a separate Foundry
project — see `Deployment.md` for setup (`forge install OpenZeppelin/openzeppelin-contracts-upgradeable`
is required before building it) and `forge test` to run the suite against a live BSC mainnet fork.
