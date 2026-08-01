# Spark — BSC Mainnet Deployment

Chain: BNB Smart Chain (BSC) mainnet, chain ID `56`.

## SparkV2

### Active contracts

All verified on BscScan (source + ABI match on-chain bytecode exactly).

| Contract | Address | Deployed block | Deploy tx |
|---|---|---|---|
| `SparkToken` (implementation) | [`0x03270BCd524071581dAB48f31E3152282801B9a9`](https://bscscan.com/address/0x03270BCd524071581dAB48f31E3152282801B9a9#code) | 113277601 | [`0x22089b...5966d`](https://bscscan.com/tx/0x22089bcafed4ff46927ae09f5f7d9a9ec61ee98ed87bf77bc0de637a4535966d) |
| `SparkLocker` | [`0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B`](https://bscscan.com/address/0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B#code) | 113277603 | [`0xdff353...49ac3`](https://bscscan.com/tx/0xdff35367fd6df5a9f9cfbf10314c1b36f234bb0d5044de8578f60822fe249ac3) |
| `SparkLauncherV2` | [`0xcD5B9F286cd5A2cE2fBe160bAfc018a1159d5c77`](https://bscscan.com/address/0xcD5B9F286cd5A2cE2fBe160bAfc018a1159d5c77#code) | 113277608 | [`0x9b0514...36c5a`](https://bscscan.com/tx/0x9b05141d8b5b06dc1821dd3acd012c5c4b5892a9e0b59dbe6c26ece2cf436c5a) |
| `SparkHookV4` | [`0x8baB0D3049B6d5D17B36d3263786Fe587A9D00C4`](https://bscscan.com/address/0x8baB0D3049B6d5D17B36d3263786Fe587A9D00C4#code) | 113278869 | [`0xb08460...67923`](https://bscscan.com/tx/0xb08460dfbf49ac73d8cb6b0284b1f476b1d4fea4e654e0020d9320f4e9467923) |
| `SparkHookInfinity` | [`0xad220d84F318Ca4941D07af5AF244f081Cb849A8`](https://bscscan.com/address/0xad220d84F318Ca4941D07af5AF244f081Cb849A8#code) | 113278027 | [`0x6145d1...889ce`](https://bscscan.com/tx/0x6145d1ae90884ed336bfd0df7149517434cd9a4cb53c92b02e3006b46d2889ce) |
| `SparkBurner` | [`0x34480Bcd62D0bed99E2782cCAaF90c31A7fB475E`](https://bscscan.com/address/0x34480Bcd62D0bed99E2782cCAaF90c31A7fB475E#code) | 113278035 | [`0xff909d...9606b0`](https://bscscan.com/tx/0xff909dcd0b5d5f80bf42a91fd5f338fef91823b0ecd3c6ce0c377ccd9ea606b0) |

`SparkHookV4` was deployed via a one-time helper factory (below) rather than directly, so that
ownership could be transferred atomically in the same transaction — see *Deprecated / abandoned*
for why.

| Helper (one-time use, not part of the ongoing system) | Address | Deployed block | Deploy tx |
|---|---|---|---|
| `HookV4Factory` | [`0xF5eAD4a17Ce34a99a1F0f0C67C5d4DF2f6500229`](https://bscscan.com/address/0xF5eAD4a17Ce34a99a1F0f0C67C5d4DF2f6500229#code) | 113278865 | [`0xc8cef9...5728f`](https://bscscan.com/tx/0xc8cef9f2a02a32a4652f71f85d2e41be2dc3c6547809f9d052b57034f7b5728f) |

Verified via `forge verify-contract` against the Etherscan V2 unified API (`--chain 56`), which
worked even for `SparkHookV4` despite it being created by an internal CREATE2 call from
`HookV4Factory` rather than a top-level deployment transaction.

### Configuration transactions

| Action | Block | Tx |
|---|---|---|
| `SparkLocker.setLauncher(SparkLauncherV2)` | 113277615 | [`0x08e195...3a5ca`](https://bscscan.com/tx/0x08e195722db21145826c7c4f2c2cca77887d561e78798892a7e64892eea3a5ca) |
| `SparkLauncherV2.addDex` — PancakeSwap Infinity → `SparkHookInfinity` | 113278031 | [`0xbeb628...db154`](https://bscscan.com/tx/0xbeb6287db78ad07a169b8d0d4e11278e950be5c37a3265a8596ab8c2ff1db154) |
| `SparkLauncherV2.setBurner(SparkBurner)` | 113278039 | [`0x26ede0...b6563b`](https://bscscan.com/tx/0x26ede0064c4638c6a83ca3e70166ec14acf44d8c48208aade0c73bdfbf36563b) |
| `SparkLauncherV2.addDex` — Uniswap v4 → `SparkHookV4` (current, correct) | 113278873 | [`0x2e8311...4b340e`](https://bscscan.com/tx/0x2e8311d630a6e17c28388b839261375322c8fa4f1710c7896b883090ad4b340e) |

### Deployed config values

- `owner` (all of `SparkLocker`, `SparkLauncherV2`, `SparkHookV4`, `SparkHookInfinity`): `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- `platformWallet` (`SparkLocker`, both hooks): `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F` (same as owner)
- `launchFeeWallet`: unset (`address(0)`) — defaults to `owner`
- `launchFee`: `0.001111 ether`
- `marketCapRef`: `5e18` (default, unchanged)
- `ctoFee` (`SparkLocker`, both hooks): `0.1 ether` (default, unchanged)
- `ctoFeeWallet` (`SparkLocker`, both hooks): unset (`address(0)`) — defaults to `owner`
- `SparkLocker.creatorBps` / `platformBps`: `7000` / `3000` (default, unchanged)
- `SparkHookV4.platformBps` / `SparkHookInfinity.platformBps`: `3000` (default, unchanged)

### External BSC mainnet dependencies

| Protocol | Contract | Address |
|---|---|---|
| Uniswap v4 | PositionManager | `0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b` |
| Uniswap v4 | PoolManager | `0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF` |
| Uniswap v4 | Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| PancakeSwap Infinity | CLPositionManager | `0x55f4c8abA71A1e923edC303eb4fEfF14608cC226` |
| PancakeSwap Infinity | Vault | `0x238a358808379702088667322f80aC48bAd5e6c4` |
| PancakeSwap Infinity | CLPoolManager | `0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b` |
| PancakeSwap Infinity | Permit2 | `0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768` |

### Deprecated / abandoned

| Contract | Address | Status |
|---|---|---|
| `SparkHookV4` (first attempt) | `0xA399849Ef491FA2ee2A02751b6440c8d5a04c0C4` | **Do not use.** Deployed directly via a salted `new SparkHookV4{salt}()` under `vm.startBroadcast()`, which Foundry routes through the canonical CREATE2 deployer proxy (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) since a plain EOA can't execute the CREATE2 opcode itself. That made the proxy `msg.sender` inside the constructor, so `owner = msg.sender` set this hook's `owner` to the proxy contract — which has no way to call anything back. Its admin functions (`transferOwnership`, `setPlatformWallet`, `approveCTO`/`rejectCTO`, etc.) are permanently uncallable by anyone. It was briefly registered as the Uniswap v4 hook (block 113278023) and immediately superseded (block 113278873) before any token was ever launched through it — no user funds or pools were ever exposed to it. The fix (`HookV4Factory` above) deploys via CREATE2 from a contract we control instead, so it can call `transferOwnership` back to the real deployer atomically in the same transaction. |
| `SparkToken` impl (first attempt) | `0xE33c47C89e57C8C3493A257Fd1b699aa5887b43E` | **Do not use.** From an earlier `DeploySparkV2` broadcast that also hit the same public RPC's "in-flight transaction limit reached for delegated accounts" error after its 4th transaction. Unrelated to the `SparkHookV4` bug above — just the same rate limit hit twice, ~3 minutes apart, on two separate full-script attempts. |
| `SparkLocker` (first attempt) | `0xFA7aB74FdC8fD10E792Ee0Bc4Cd6fd34e439AC08` | **Do not use.** Paired with the abandoned token impl and launcher above; `setLauncher` was called on it, but nothing else. |
| `SparkLauncherV2` (first attempt) | `0x494BD7CA07Ce1FFDF4CAaCf117B30dF29e48c742` | **Do not use.** No hook or burner was ever configured on this instance — `dexes(V4_POSITION_MANAGER).hook == address(0)`, so `launch()` unconditionally reverts (`HookRequired`) on it. Structurally inert; safe to ignore. |

### Reproducing this deployment

Scripts live in [`deploy/`](deploy/) (a separate Foundry project, gitignored `lib/`/`out/`/`cache/`):

- `script/DeploySparkV2.s.sol` — full from-scratch deployment (token impl, locker, launcher, both hooks, burner, all wiring).
- `script/HookV4Factory.sol` + `script/FixSparkHookV4.s.sol` — the CREATE2-via-proxy ownership fix pattern for `SparkHookV4` specifically; reusable if a hook ever needs redeploying.

## SparkV1

V3-style launcher (`spark/SparkLauncher.sol`) — seeds one-sided liquidity into standard Uniswap
V3 / PancakeSwap V3 pools (no custom hook), so launched tokens are tradeable directly through
either DEX's normal swap interface. Deployed after SparkV2 specifically to fix the tradability gap
SparkV2 has: SparkV2's Uniswap v4 / PancakeSwap Infinity pools use a custom hook and a `fee: 0`
pool key, which neither DEX's frontend discovers or routes through by default, and most trading
bots don't support hooked v4/Infinity pools at all. SparkV1 uses the standard V3 fee-tier system
instead, so pools are found and routable everywhere V3 already works.

Uses a **separate `SparkLocker`** instance from SparkV2's — `SparkLocker` only tracks a single
`launcher` address (`onlyLauncher` gate on `registerPosition`), so pointing it at a second launcher
would have retired SparkV2's ability to register new positions. Deploying a second locker keeps
both launchers independently live.

Before this deployment, two fixes were made to `spark/SparkLauncher.sol` (neither present in the
original, undeployed version of the contract):

- **`ISwapRouter` ABI fix.** The original interface was missing `deadline` from
  `ExactInputSingleParams`/`ExactInputParams`, which matches Uniswap's newer `SwapRouter02`
  (`IV3SwapRouter`, no `deadline`) but not PancakeSwap's `SwapRouter`/`SmartRouter`, which kept the
  original `ISwapRouter` shape (`deadline` included). Since the two DEXes registered here use
  different router ABIs, `DexConfig` gained a `routerNoDeadline` flag and `_doInstantBuy` now
  branches between two router interfaces based on it, instead of assuming one shape for every
  registered DEX.
- **Vanity salt.** `launch()` gained a `vanitySalt_` parameter (`keccak256(abi.encode(msg.sender,
  vanitySalt_))`, replacing the old `msg.sender + block.timestamp`-derived salt), and every launched
  token's clone address must now end in `0x1111` (`VANITY_SUFFIX`, checked in `_deployAndInit`,
  reverts `VanityMismatch()` otherwise) — same mechanism and suffix as SparkV2. The existing
  [`spark-v2/saltminer/`](spark-v2/saltminer/index.html) tool works unmodified for SparkV1: its salt
  formula matches exactly, it just needs SparkV1's launcher/impl addresses instead of SparkV2's.

### Active contracts

All verified on BscScan (source + ABI match on-chain bytecode exactly). `SparkToken` and
`SparkLocker` verified via BscScan's bytecode-match auto-detection against SparkV2's already-verified
source, since both contracts are byte-identical (no constructor-arg-dependent bytecode) to their
SparkV2 counterparts.

| Contract | Address | Deployed block | Deploy tx |
|---|---|---|---|
| `SparkToken` (implementation) | [`0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA`](https://bscscan.com/address/0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA#code) | 113379800 | [`0xf3bc1c...31747`](https://bscscan.com/tx/0xf3bc1c6bce6c6f2c2c4b9fe9027558c0ad8a5bee6685543ae5e1c0c8cb631747) |
| `SparkLocker` | [`0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86`](https://bscscan.com/address/0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86#code) | 113379804 | [`0xfa87c5...4952a`](https://bscscan.com/tx/0xfa87c5f6f6face1255598674d830c815ae81085bc8d9ae621843d3501f64952a) |
| `SparkLauncher` | [`0x1Bfc2A7d68A115B29906537D9E836A1799ebd3C4`](https://bscscan.com/address/0x1Bfc2A7d68A115B29906537D9E836A1799ebd3C4#code) | 113379808 | [`0xec4313...20ba06`](https://bscscan.com/tx/0xec431334d9ec0f381e067bb2b00efaaa2fe4df6d2e608cf123cc29c3db20ba06) |

### Configuration transactions

| Action | Block | Tx |
|---|---|---|
| `SparkLocker.setLauncher(SparkLauncher)` | 113379813 | [`0x11e55d...05b22`](https://bscscan.com/tx/0x11e55d9c986ae493497a2d55781779ca02ca6116fd06442009f8515bb7505b22) |
| `SparkLauncher.addDex` — Uniswap V3 | 113379817 | [`0x871a39...6efc3`](https://bscscan.com/tx/0x871a39e48f7080d7af736e84f4177f1d3423a92447ca51fc13530f11aa16efc3) |
| `SparkLauncher.addQuoteToken` — USDT | 113379821 | [`0x9b4afe...9d62e6`](https://bscscan.com/tx/0x9b4afeaebc5d1394f04be0c7590a699c2bf227dcea906c95c0b37dfe729d62e6) |
| `SparkLauncher.addQuoteToken` — USDC | 113379825 | [`0x42958d...d65b34d`](https://bscscan.com/tx/0x42958d6b3cfd44d678096109c44b01d565e905f90d01a5712e262e5d6d65b34d) |
| `SparkLauncher.addQuoteToken` — USD1 | 113379829 | [`0xb385e4...7513b43eb`](https://bscscan.com/tx/0xb385e43c15a1989b540714b98b0e40f7eb01fd4bb5c1263fd22b59b7513b43eb) |

### Deployed config values

- `owner` (`SparkLocker`, `SparkLauncher`): `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- `platformWallet` (`SparkLocker`): `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F` (same as owner)
- `launchFeeWallet`: unset (`address(0)`) — defaults to `owner`
- `launchFee`: `0.001111 ether`
- Initial DEX: PancakeSwap V3 (`routerNoDeadline: false`) — Factory `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865`, PositionManager `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364`, SmartRouter `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4`
- Second DEX: Uniswap V3 (`routerNoDeadline: true`) — Factory `0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7`, PositionManager `0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613`, SwapRouter02 `0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2`
- Quote tokens: WBNB (`marketCapRef` `5e18`, default) plus USDT/USDC/USD1 (`marketCapRef` `3000e18` each, ≈$3,000 initial market cap)
- `FEE_TIER`: `10_000` (1%, default, unchanged)

### Quote tokens

| Token | Address | `marketCapRef` | `wethPairFee` (deepest WBNB pool on PancakeSwap V3) |
|---|---|---|---|
| WBNB | `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c` | `5e18` | n/a |
| USDT | `0x55d398326f99059fF775485246999027B3197955` | `3000e18` | `500` (0.05%) |
| USDC | `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d` | `3000e18` | `100` (0.01%) |
| USD1 | `0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d` | `3000e18` | `100` (0.01%) |

bStocks (Binance's tokenized-equity BEP-20s, e.g. TSLAB) were deliberately **not** added as quote
tokens in this deployment: only TSLAB's address could be independently confirmed (verified
on-chain via `name()`/`symbol()`), no other bStocks ticker's address could be confirmed with the
same confidence, and the tokens use an issuer-upgradeable beacon-proxy pattern plus an EIP-8056
rebase mechanism for dividends/splits whose interaction with Uniswap V3 pool accounting wasn't
independently verified against source. Addable later via `addQuoteToken()` (owner-only, no
redeploy needed) once addresses are confirmed and the rebase risk is reviewed.

### Deprecated / abandoned

Two earlier broadcasts of `DeploySparkV1.s.sol` (without `--slow`) hit the same public RPC
in-flight-transaction-limit issue documented under SparkV2 above — mid-run, forge stopped
receiving responses and exited before recording a hash locally, but the already-submitted
transaction had, in both cases, actually landed on-chain by the time the process died. Unlike
SparkV2's abandoned attempts, **these are not inert** — each has both PancakeSwap V3 and Uniswap V3
correctly registered (`addDex` did land), so a WBNB-quoted `launch()` call would succeed against
either. Only `addQuoteToken` (USDT/USDC/USD1) never got submitted before the process died.
Confirmed via `tokenCount()` that no tokens were ever launched through either. **Do not use.**

| Contract | Address | Status |
|---|---|---|
| `SparkLauncher` (1st attempt) | `0x35E7a3ac6BE1bb8b81b94A1Dd503F9Bf23814EE0` | **Do not use.** Missing USDT/USDC/USD1 quote tokens; WBNB-only. |
| `SparkLocker` (1st attempt) | `0xF1853873066AF8f51a7C4585C1C98f0Af885bea3` | **Do not use.** Paired with the launcher above; `setLauncher` succeeded, `tokenCount() == 0`. |
| `SparkToken` impl (1st attempt) | `0xe7f3021F26692EAFEC780f2440EDf94907fDb0D7` | **Do not use.** Paired with the launcher above. |
| `SparkLauncher` (2nd attempt) | `0xaBF538b0fa17DF5c07Bb705532C0b2319C22BEcB` | **Do not use.** Same failure mode as the 1st attempt. |
| `SparkLocker` (2nd attempt) | `0xFc272B3Bd881f10c98403b00480B1eA4A88f151C` | **Do not use.** Paired with the launcher above; `setLauncher` succeeded, `tokenCount() == 0`. |
| `SparkToken` impl (2nd attempt) | `0xa9838DBBca8780Fb327E7f03D9dEfDF2Ab25312c` | **Do not use.** Paired with the launcher above. |

### Reproducing this deployment

`script/DeploySparkV1.s.sol` — full from-scratch deployment (token impl, new locker, launcher,
Uniswap V3 registered as a second DEX, USDT/USDC/USD1 registered as quote tokens). Run with
`--slow` to send transactions one at a time rather than batched — the SparkV2 deployment above (and
the two abandoned SparkV1 attempts) hit a public RPC's in-flight transaction limit doing the
latter.
