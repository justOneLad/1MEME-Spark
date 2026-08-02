# Spark — BSC Mainnet Deployment

Chain: BNB Smart Chain (BSC) mainnet, chain ID `56`.

Two independent, UUPS-upgradeable launcher families are live: **SparkLauncher**
(plain Uniswap V3 / PancakeSwap V3 pools) and **SparkGo** (hook-gated Uniswap
v4 / PancakeSwap Infinity singleton pools). Both share a bounded-fallback
instant-buy routing engine (`common/SparkRouting.sol`) and support arbitrary
quote tokens, not just native BNB.

## Why a shared routing engine

Registering tokenized-stock quote tokens surfaced the problem
`common/SparkRouting.sol` exists to fix: several (AAPL/NVDA/TSLA/SPCX,
Ondo-tokenized) have **no real WBNB liquidity at all** on PancakeSwap V3 —
only empty-shell pools or none — so a naive single-hardcoded-hop instant-buy
silently couldn't work for any of them. The real liquidity mostly sits in
USDT pools instead, and SPCX's *only* real liquidity is on Uniswap V3 while
the deepest WBNB/USDT liquidity is on PancakeSwap — two different DEXs.

`SparkRouting` replaces the single hardcoded hop with an owner-configured,
ordered list of concrete fallback routes per quote token — tried in turn via
`try this.X() {} catch {}` — across 4 route shapes covering 6 nominal
protocols (Uniswap/PancakeSwap V2 share one router ABI; Uniswap/PancakeSwap V3
share one shape via a `routerNoDeadline` flag; Uniswap v4 and PancakeSwap
Infinity both use a singleton-pool-manager unlock/lock callback, generalized
to handle arbitrary currency-in/currency-out pairs so the same engine serves
both SparkLauncher's leg-1 routing *and* SparkGo's leg-2 instant-buy against
its own newly-created pool). A single logical route can also chain hops
across *different* DEXs (`Route.routers[]`, one router per hop) — exactly
SPCX's case: PancakeSwap for the WBNB→USDT leg, Uniswap for USDT→SPCX. Both
launchers have real `minQuoteOut`/`minTokensOut` slippage floors and a
`revertOnInstantBuyFailure` flag — skip-and-refund by default so a routing
hiccup doesn't hold the whole launch hostage, or full revert if the creator
wants that atomicity.

`SparkGo`'s `currency0` is whichever of `(quoteToken, token)` sorts lower, not
hardcoded `address(0)` — which cascades into both hooks (`SparkGoHookV4`/
`SparkGoHookInfinity`) and `SparkGoBurner` taking/paying/tracking fees in
whatever currency a pool actually uses. Hooks and the burner are **plain,
non-upgradeable** contracts by design — a hook executes on every swap of
every pool already using it, so upgradeability there would let the owner
rewrite the rules of pools with live user funds retroactively; a launcher
upgrade only shapes future launches. `tokenHook[token]` snapshots the hook at
launch time, so redeploying a hook and repointing via `addDex` leaves
existing pools untouched.

## Fork-test validation

`deploy/test/` — real BSC mainnet fork (`vm.createSelectFork`), not testnet
(see *Reproducing this deployment* below for why). 13/13 passing as of this
write-up:

| Suite | Coverage |
|---|---|
| `ProxyUpgrade.t.sol` | Trivial mock implementations behind a real `ERC1967Proxy` — init-once, direct-implementation-init blocked, storage survives an upgrade, only-owner can upgrade. |
| `SparkLauncherFork.t.sol` | Real `SparkLauncher` behind a proxy. Plain WBNB-quoted launch. NVDA-quoted launch via a real WBNB→USDT→NVDA multihop route. **SPCX-quoted launch via a cross-DEX chained route** (PancakeSwap then Uniswap, one route). All-routes-failing with `revertOnInstantBuyFailure: false` skip-and-refunds cleanly. Full lifecycle: trade → fees accrue → claim → CTO. |
| `SparkGoLauncherFork.t.sol` | Real `SparkGoLauncher` + a CREATE2-mined `SparkGoHookV4` behind a proxy. Native-BNB-quoted launch. ERC20-quoted launches in **both** address orderings (token as `currency0` and `currency1`). Full lifecycle: trade → fees accrue → claim → CTO → burner claims/swaps/burns. |

## Reproducing this deployment

Scripts live in [`deploy/`](deploy/) (a separate Foundry project, gitignored
`lib/`/`out/`/`cache/`; `forge install OpenZeppelin/openzeppelin-contracts-upgradeable`
needed before building):

- `script/DeploySparkUpgradeable.s.sol` — deploys `SparkLauncher` behind a
  proxy, reuses the existing `SparkToken` impl and `SparkLocker` (repointed
  via `setLauncher`), registers PancakeSwap V3 + Uniswap V3, and
  WBNB/USDT/USDC/USD1/AAPL/NVDA/TSLA/SPCX quote tokens with real fallback
  routes (SPCX's is cross-DEX chained).
- `script/DeploySparkGo.s.sol` — deploys `SparkGoLauncher` behind a proxy,
  reuses the existing `SparkToken` impl and `SparkLocker` (repointed via
  `setLauncher`), deploys fresh `SparkGoHookV4`/`SparkGoHookInfinity`/
  `SparkGoBurner`, and registers the same quote-token/route set.
- `script/SparkGoHookFactory.sol` — one-time CREATE2-ownership-fixup helper:
  `SparkGoHookV4`'s deployed address needs specific low bits
  (`REQUIRED_PERMISSIONS`), which forces the CREATE2 deployer proxy as
  `msg.sender` inside the constructor — this factory transfers ownership to
  the real deployer atomically in the same transaction.

Both scripts are **broadcast and live** on BSC mainnet — see each launcher's
*Active contracts* section below for real addresses/tx hashes.

Two real deployment-*process* gotchas surfaced during broadcast, independent
of contract logic (fork tests already covered that):

- **Most public/shared BSC RPC endpoints can't complete a `--broadcast` run.**
  `forge script` always runs a first full simulation to build the transaction
  list (this consistently succeeded, every attempt, on every RPC tried), then
  a second on-chain verification pass right before actually sending — and
  every free/shared endpoint tried (`bsc-dataseed.binance.org`,
  `bsc.publicnode.com`, a GetBlock shared node, `binance.nodereal.io`) failed
  that second pass with some variant of "missing trie node" / "historical
  state not available" / an archive-request paywall. Not an RPC-choice
  problem so much as a Foundry-vs-non-archive-node interaction — the fix is
  `--skip-simulation` (broadcast directly from the first, already-successful
  simulation's transaction list), now baked into `deploy-all.sh`.
- `bsc.publicnode.com`'s free tier additionally gates `eth_getTransactionReceipt`
  itself behind an archive-request paywall mid-sequence — a transaction can
  succeed on-chain while forge still reports a failure fetching its receipt.
  Always verify on-chain state directly (`cast call`/`cast receipt` against a
  different endpoint) before assuming a transaction actually failed.

Run both in one command via the wrapper (defaults to `binance.nodereal.io`,
proven reliable for a full broadcast):

```
./deploy-all.sh <private-key> [rpc-url]
```

or individually:

```
forge script script/DeploySparkUpgradeable.s.sol:DeploySparkUpgradeable --rpc-url https://binance.nodereal.io --broadcast --slow --skip-simulation --private-key <key>
forge script script/DeploySparkGo.s.sol:DeploySparkGo               --rpc-url https://binance.nodereal.io --broadcast --slow --skip-simulation --private-key <key>
```

Fork-first, not testnet, as the correctness gate: testnet doesn't have
reliable coverage of all 6 routing protocols (or the real AAPL/NVDA/TSLA/SPCX
WBNB liquidity gaps this engine exists to route around) the way a mainnet
fork does.

## Shared contracts (reused by both launchers)

| Contract | Address | Deployed block | Deploy tx |
|---|---|---|---|
| `SparkToken` (implementation) | [`0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA`](https://bscscan.com/address/0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA#code) | 113379800 | [`0xf3bc1c...31747`](https://bscscan.com/tx/0xf3bc1c6bce6c6f2c2c4b9fe9027558c0ad8a5bee6685543ae5e1c0c8cb631747) |
| `SparkLocker` (SparkLauncher's) | [`0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86`](https://bscscan.com/address/0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86#code) | 113379804 | [`0xfa87c5...4952a`](https://bscscan.com/tx/0xfa87c5f6f6face1255598674d830c815ae81085bc8d9ae621843d3501f64952a) |
| `SparkLocker` (SparkGo's) | [`0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B`](https://bscscan.com/address/0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B#code) | 113277603 | [`0xdff353...49ac3`](https://bscscan.com/tx/0xdff35367fd6df5a9f9cfbf10314c1b36f234bb0d5044de8578f60822fe249ac3) |

Both `SparkLocker`s predate this deployment (each was originally paired with
an earlier launcher version) but are **actively reused**, repointed at the
current proxies below via `setLauncher` — `onlyLauncher` only gates
`registerPosition`, not fee claims, so repointing doesn't affect any
already-launched token's ability to claim fees.

---

## SparkLauncher

V3-style launcher — seeds one-sided liquidity into standard Uniswap V3 /
PancakeSwap V3 pools (no custom hook), so launched tokens are tradeable
directly through either DEX's normal swap interface.

### Active contracts

Deployed via `DeploySparkUpgradeable.s.sol`, `--skip-simulation`. All
addresses/state confirmed directly on-chain via `cast call` after broadcast,
independent of forge's own reporting.

| Contract | Address | Deployed block | Deploy tx |
|---|---|---|---|
| `SparkLauncher` (implementation) | `0xE4dD59Fb5b78a5f92fCf4A42154f582A18b4f1f0` | 113582644 | [`0xebf5ff...ca333`](https://bscscan.com/tx/0xebf5ff5afa05e1ae03b7211612b73c94492619bfa0414882a49fa9488edca333) |
| `SparkLauncher` (proxy, use this address) | `0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973` | 113582648 | [`0x9c7896...ad37b`](https://bscscan.com/tx/0x9c7896bb55f06733387d26596d61f769a0c35d2d71e84cfd8bf4e943cb3ad37b) |

#### Configuration transactions

| Action | Block | Tx |
|---|---|---|
| `SparkLocker.setLauncher(proxy)` | 113582653 | [`0x2f27ea...60560`](https://bscscan.com/tx/0x2f27eab47cee942b37f9075b844b2fc824b3f06b75bb2a44f6bdf4bcbec40560) |
| `addDex` — Uniswap V3 | 113582656 | [`0x425599...15921`](https://bscscan.com/tx/0x4255994e1e7ba7ee97a72afca853305b56064eb60214cd663964ed129c15e921) |
| `addQuoteToken` — USDT | 113582660 | [`0xac5cf7...8a5c9`](https://bscscan.com/tx/0xac5cf7d96a975ec3b6b2440d7c86eda930cfcd8773be5ee715112039de78a5c9) |
| `addQuoteToken` — USDC | 113582664 | [`0x5c2ee0...96a3a6`](https://bscscan.com/tx/0x5c2ee0dadeace60657cb77a8f477e0233c8f77d9008debbfe3d7b56c9c96a3a6) |
| `addQuoteToken` — USD1 | 113582668 | [`0x091401...ab4d3fc`](https://bscscan.com/tx/0x0914019b87115a86f37bee61dfadbf541f14661f24835d796a8075acaab4d3fc) |
| `addQuoteToken` — AAPL | 113582673 | [`0x09c363...63145`](https://bscscan.com/tx/0x09c36333482a1ef3d3a011a3eb7e49438548e2306aa803952a003e79f5f63145) |
| `addQuoteToken` — NVDA | 113582676 | [`0x43d522...23d8d`](https://bscscan.com/tx/0x43d52279a4c2f83e258c76e38d49de3562b7ff7dbb1915818437ce0e15323d8d) |
| `addQuoteToken` — TSLA | 113582680 | [`0xbfd179...16213`](https://bscscan.com/tx/0xbfd179538338b6c7b4bde7ab1e3b70ab9f442371fad6163bb103f4dbf7916213) |
| `addQuoteToken` — SPCX | 113582685 | [`0x87ffbc...51b7`](https://bscscan.com/tx/0x87ffbcfc7c4709c1b2764e568f7ee48292aa4e826a6903e038a77ad9178151b7) |
| `setRoutes` — USDT (single-hop, PancakeSwap) | 113582688 | [`0xb80123...c0e14`](https://bscscan.com/tx/0xb80123dd0e507fc60ce51df76840a63b4ef83cb654021744c7a067e1528c0e14) |
| `setRoutes` — USDC (single-hop, PancakeSwap) | 113582692 | [`0x35d055...1d24732`](https://bscscan.com/tx/0x35d05554fefafe70255e1ae494a5455144715339112a84365b673abda1d24732) |
| `setRoutes` — USD1 (single-hop, PancakeSwap) | 113582697 | [`0x425ea4...4b3b43`](https://bscscan.com/tx/0x425ea4092db927e95759b70082c7e45cfd7eae7d88d2443b95a5e68cce4b3b43) |
| `setRoutes` — AAPL (multi-hop via USDT, PancakeSwap) | 113582701 | [`0x35e6d2...9601f`](https://bscscan.com/tx/0x35e6d2a248c93e0ae304b146a54aa1d4554ef7603137bd069dcfb3e228b9601f) |
| `setRoutes` — NVDA (multi-hop via USDT, PancakeSwap) | 113582705 | [`0xfde578...70dc4d8`](https://bscscan.com/tx/0xfde578a776645b14b7e2db030eee551c528405b58c181c4f8446a951670dc4d8) |
| `setRoutes` — TSLA (multi-hop via USDT, PancakeSwap) | 113582709 | [`0xc14d4c...ad65b5`](https://bscscan.com/tx/0xc14d4c024d1c55cc336a762aa90b774203079a7cc339fd1db5189c3c0fad65b5) |
| `setRoutes` — SPCX (cross-DEX chained: PancakeSwap WBNB→USDT, Uniswap USDT→SPCX) | 113582713 | [`0x408281...fbe34`](https://bscscan.com/tx/0x4082817ccf9993d7403a6ae5b14ac4bdbd6ab1334260f45815453d78b7dfbe34) |

#### Deployed config values

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- Initial DEX: PancakeSwap V3, `routerNoDeadline: true` — Factory `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865`, PositionManager `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364`, SmartRouter `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4`
- Second DEX: Uniswap V3, `routerNoDeadline: true` — Factory `0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7`, PositionManager `0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613`, SwapRouter02 `0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2`
- `launchFee`: `0.001111 ether`
- Quote tokens (`marketCapRef`): WBNB `5e18` (default) · USDT/USDC/USD1 `2000e18` each · AAPL `6.629321488945606656e18` · NVDA `10.0664384940608e18` · TSLA `4.788469365767232512e18` · SPCX `18.348623853211009024e18` (all ≈$2,000 initial launch market cap at deploy-time prices)
- Routes: single-hop PancakeSwap V3 for USDT/USDC/USD1; multi-hop (WBNB→USDT→stock) via PancakeSwap V3 for AAPL/NVDA/TSLA; **cross-DEX chained route** for SPCX — PancakeSwap V3 for the WBNB→USDT leg, Uniswap V3 for the USDT→SPCX leg (SPCX's only real liquidity)

---

## SparkGo

Currency-general, hook-gated launcher (Uniswap v4 / PancakeSwap Infinity
singleton pools with a mandatory anti-sandwich / max-buy-wallet / 2%-sell-fee
hook).

### Active contracts

Deployed via `DeploySparkGo.s.sol`, `--skip-simulation`. Succeeded
start-to-finish in one run. All state confirmed directly on-chain via
`cast call` after broadcast.

| Contract | Address | Deployed block | Deploy tx |
|---|---|---|---|
| `SparkGoLauncher` (implementation) | `0x8AE5052A18439D7120124AB1356b5A1cD19606A8` | 113583458 | [`0xe93801...67e2`](https://bscscan.com/tx/0xe938018f1f62eb35d37f661ca444f915bbc57f8f2fe394e5509cdfbd8de667e2) |
| `SparkGoLauncher` (proxy, use this address) | `0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C` | 113583462 | [`0xa3294e...668b6f`](https://bscscan.com/tx/0xa3294eace958266778595a8d19890377554de2d06c5e0ff9b7eff27782668b6f) |
| `SparkGoHookFactory` (one-time helper) | `0xF3DF835378eC75346b66b7821e501ebAf535Fa16` | 113583470 | [`0xaba692...c9d2b`](https://bscscan.com/tx/0xaba6925ca99fd2783aead66f96f0d74fa014b3d16092e78b8b37f57db1cc9d2b) |
| `SparkGoHookV4` | `0xdF3f8b41a55fb8737D653d6bc7467095e48700c4` | 113583474 | [`0xf1d712...cdc31`](https://bscscan.com/tx/0xf1d7127eb1a874a84c383c8ce36af9ae58b9ead8e69b5f16a349a922f19cdc31) |
| `SparkGoHookInfinity` | `0x8E273c882267f034ACE21dA677dBF0c0eB305B82` | 113583482 | [`0x630cd0...ad25`](https://bscscan.com/tx/0x630cd0d2458fc799113ac47611a0e8c284fe4a7e4e0d704e0de46446eaf1ad25) |
| `SparkGoBurner` | `0xC99fD815f5C0a5dCf2B6cA36A38AbbB5cF4e4c10` | 113583491 | [`0xfb68bb...feeac6`](https://bscscan.com/tx/0xfb68bb73a8af506ec5352b0f62d5206099c67123247f5f089fdfc241f4feeac6) |

`SparkGoHookV4` deployed via `SparkGoHookFactory` — confirmed low 14 address
bits equal `0xC4` (`REQUIRED_PERMISSIONS`) and `owner() == deployer` on-chain.
`SparkGoHookInfinity`'s `getHooksRegistrationBitmap()` confirmed equal to
`REQUIRED_BITMAP()` (`2240`) on-chain.

#### Configuration transactions

| Action | Block | Tx |
|---|---|---|
| `SparkLocker.setLauncher(proxy)` | 113583466 | [`0xa544b2...e8ac7`](https://bscscan.com/tx/0xa544b22ee89b9683556a842c62eed58a2e0264f2519c59f615c141cde33e8ac7) |
| `addDex` — Uniswap v4 → `SparkGoHookV4` | 113583478 | [`0xac9b37...b598d`](https://bscscan.com/tx/0xac9b37cb0a28d87cb4508837e059e8218b1f51cec4ee7e46ec75a9f47ffb598d) |
| `addDex` — PancakeSwap Infinity → `SparkGoHookInfinity` | 113583486 | [`0x691335...52d8cf`](https://bscscan.com/tx/0x691335decb59d912393111229e27d90d821615aa45e68bffd64d421e1352d8cf) |
| `setBurner(SparkGoBurner)` | 113583495 | [`0x35c973...b0a7644`](https://bscscan.com/tx/0x35c973afa8cc49327926ebe136280fcbfa216c1eabb98e707ecf945fdb0a7644) |
| `addQuoteToken` — USDT | 113583499 | [`0x55099d...15e86e`](https://bscscan.com/tx/0x55099d2e9efc5df24bcf09fe5f9bd13b34f8259ed56a82f425d2aa84b115e86e) |
| `addQuoteToken` — USDC | 113583503 | [`0x004d4a...363e5`](https://bscscan.com/tx/0x004d4a6897a3abac9a98ce83bb31acac0b7447c8b7e5339aa62ae868685363e5) |
| `addQuoteToken` — USD1 | 113583507 | [`0xa1dc94...affe6`](https://bscscan.com/tx/0xa1dc9422c554d17764277d189299990076e481ab31fa7135332f1e48f79affe6) |
| `addQuoteToken` — AAPL | 113583511 | [`0xb93c58...d8315`](https://bscscan.com/tx/0xb93c58577d80c04caef3e431ed13d0f21d8ad3cf3c5c47d73ee773a3396d8315) |
| `addQuoteToken` — NVDA | 113583515 | [`0x697efe...29b5b6`](https://bscscan.com/tx/0x697efee60b2ec2330f86c7477b06e1f194a0ea99ffc4d9d94c5a93020429b5b6) |
| `addQuoteToken` — TSLA | 113583519 | [`0x807960...19c9d`](https://bscscan.com/tx/0x807960f88e0d4f1c62875e0516295656f7e55f07cb739a068cdae8a233d19c9d) |
| `addQuoteToken` — SPCX | 113583523 | [`0x4d03fe...6b9d951`](https://bscscan.com/tx/0x4d03feda0839f95b5257c185d5937d6a620c06f8e5de2a7864f6037e66b9d951) |
| `setRoutes` — USDT (single-hop, PancakeSwap) | 113583528 | [`0x7f00c9...eb40e`](https://bscscan.com/tx/0x7f00c9020689baf79db08ab9ef5b54a3ba22c43117397c5c43fa01fb0abeb40e) |
| `setRoutes` — USDC (single-hop, PancakeSwap) | 113583531 | [`0x78d74a...b13e1`](https://bscscan.com/tx/0x78d74a264178c91ad2d317c1cb2068ac394c39c5c6b19020e308b4bc9b6b13e1) |
| `setRoutes` — USD1 (single-hop, PancakeSwap) | 113583535 | [`0x198b99...f9043c`](https://bscscan.com/tx/0x198b99db4c3732b6743e8f9718e58898838384ebbf51763fd498f53f0cf9043c) |
| `setRoutes` — AAPL (multi-hop via USDT, PancakeSwap) | 113583539 | [`0xace043...c474a54`](https://bscscan.com/tx/0xace043e0d9050081da39f46a7041289c1a457c03e5ee98b5c68288825c474a54) |
| `setRoutes` — NVDA (multi-hop via USDT, PancakeSwap) | 113583543 | [`0xd301c0...86141a6`](https://bscscan.com/tx/0xd301c0a5a5028dc1294387587ea857bc46cc94dfd864ff2577ac855e586141a6) |
| `setRoutes` — TSLA (multi-hop via USDT, PancakeSwap) | 113583547 | [`0x81791d...9b54c76`](https://bscscan.com/tx/0x81791dddd3d406bbea8cdc76a7149db8a67c0e12b21f31bb2e90d305b9b54c76) |
| `setRoutes` — SPCX (cross-DEX chained: PancakeSwap WBNB→USDT, Uniswap USDT→SPCX) | 113583551 | [`0xefb60f...b3546b62f28405`](https://bscscan.com/tx/0xefb60f04b247f324583140d6cd8fa5f1f4b87deb6c6f0ab488b3546b62f28405) |

#### Deployed config values

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- `launchFee`: `0.001111 ether`, `burner`: `0xC99fD815f5C0a5dCf2B6cA36A38AbbB5cF4e4c10`
- Native BNB quote token (`address(0)`): `marketCapRef` `5e18` (auto-registered in `initialize`)
- Other quote tokens (`marketCapRef`): same set and values as SparkLauncher above — USDT/USDC/USD1 `2000e18` each, AAPL/NVDA/TSLA/SPCX at their ≈$2,000-launch-marketcap references
- Routes: identical shape to SparkLauncher above — single-hop PancakeSwap for stables, multi-hop via USDT for AAPL/NVDA/TSLA, cross-DEX chained route for SPCX — the same `SparkRouting` engine genuinely shared between both launcher families

## External BSC mainnet dependencies

| Protocol | Contract | Address |
|---|---|---|
| Uniswap v4 | PositionManager | `0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b` |
| Uniswap v4 | PoolManager | `0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF` |
| Uniswap v4 | Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| PancakeSwap Infinity | CLPositionManager | `0x55f4c8abA71A1e923edC303eb4fEfF14608cC226` |
| PancakeSwap Infinity | Vault | `0x238a358808379702088667322f80aC48bAd5e6c4` |
| PancakeSwap Infinity | CLPoolManager | `0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b` |
| PancakeSwap Infinity | Permit2 | `0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768` |
| PancakeSwap V3 | Factory | `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865` |
| PancakeSwap V3 | PositionManager | `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364` |
| PancakeSwap V3 | SmartRouter (no-deadline ABI) | `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4` |
| Uniswap V3 | Factory | `0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7` |
| Uniswap V3 | PositionManager | `0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613` |
| Uniswap V3 | SwapRouter02 (no-deadline ABI) | `0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2` |
| Uniswap V2 | Router | `0x8547e2E16783Fdc559C435fDc158d572D1bD0970` |
| PancakeSwap V2 | Router | `0x10ED43C718714eb63d5aA57B78B54704E256024E` |
| — | WBNB | `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c` |
| — | USDT | `0x55d398326f99059fF775485246999027B3197955` |
| — | USDC | `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d` |
| — | USD1 | `0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d` |
| — | AAPL (Ondo Tokenized) | `0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4` |
| — | NVDA (Ondo Tokenized) | `0xA9eE28C80f960B889dFbd1902055218cBa016F75` |
| — | TSLA (Ondo Tokenized) | `0x2494b603319d4D9F9715c9f4496d9E0364B59d93` |
| — | SPCX (Ondo Tokenized) | `0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928` |

## Superseded / abandoned addresses — do not use

Every earlier launcher version and every failed/partial deploy attempt this
project went through. Bytecode is permanent on BSC regardless of what's in
this repo, so these are kept as a minimal do-not-use pointer, not a source of
truth — none of this source exists in the workspace anymore.

| Address | Former role |
|---|---|
| `0x1Bfc2A7d68A115B29906537D9E836A1799ebd3C4` | Non-upgradeable `SparkLauncher` — superseded by the proxy above |
| `0x35E7a3ac6BE1bb8b81b94A1Dd503F9Bf23814EE0`, `0xF1853873066AF8f51a7C4585C1C98f0Af885bea3`, `0xe7f3021F26692EAFEC780f2440EDf94907fDb0D7` | Non-upgradeable `SparkLauncher`/`SparkLocker`/`SparkToken` — abandoned 1st attempt, RPC in-flight-limit hit mid-broadcast |
| `0xaBF538b0fa17DF5c07Bb705532C0b2319C22BEcB`, `0xFc272B3Bd881f10c98403b00480B1eA4A88f151C`, `0xa9838DBBca8780Fb327E7f03D9dEfDF2Ab25312c` | Non-upgradeable `SparkLauncher`/`SparkLocker`/`SparkToken` — abandoned 2nd attempt, same failure mode |
| `0xcD5B9F286cd5A2cE2fBe160bAfc018a1159d5c77` | Legacy `SparkLauncherV2` — superseded by SparkGo's proxy above |
| `0x03270BCd524071581dAB48f31E3152282801B9a9`, `0x8baB0D3049B6d5D17B36d3263786Fe587A9D00C4`, `0xad220d84F318Ca4941D07af5AF244f081Cb849A8`, `0x34480Bcd62D0bed99E2782cCAaF90c31A7fB475E`, `0xF5eAD4a17Ce34a99a1F0f0C67C5d4DF2f6500229` | Legacy `SparkToken`/`SparkHookV4`/`SparkHookInfinity`/`SparkBurner`/`HookV4Factory` — all superseded by SparkGo's current contracts above |
| `0xA399849Ef491FA2ee2A02751b6440c8d5a04c0C4` | Legacy `SparkHookV4` first attempt — CREATE2-deployer-proxy ownership bug, admin functions permanently uncallable |
| `0xE33c47C89e57C8C3493A257Fd1b699aa5887b43E`, `0xFA7aB74FdC8fD10E792Ee0Bc4Cd6fd34e439AC08`, `0x494BD7CA07Ce1FFDF4CAaCf117B30dF29e48c742` | Legacy `SparkToken`/`SparkLocker`/`SparkLauncherV2` — abandoned first attempt, RPC in-flight-limit hit |
| `0x663c9Fe958E8A78a52Ba080F7EcC66DfAA6f885C`, `0xFfD11a3a10DfA21312b43B453CC8B5C75DAcC37b` | Upgradeable `SparkLauncher` implementation/proxy — abandoned attempt, stalled 3/18 txs in on a flaky RPC, restarted clean |
