# SparkV2 — BSC Mainnet Deployment

Chain: BNB Smart Chain (BSC) mainnet, chain ID `56`.

## Active contracts

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

## Configuration transactions

| Action | Block | Tx |
|---|---|---|
| `SparkLocker.setLauncher(SparkLauncherV2)` | 113277615 | [`0x08e195...3a5ca`](https://bscscan.com/tx/0x08e195722db21145826c7c4f2c2cca77887d561e78798892a7e64892eea3a5ca) |
| `SparkLauncherV2.addDex` — PancakeSwap Infinity → `SparkHookInfinity` | 113278031 | [`0xbeb628...db154`](https://bscscan.com/tx/0xbeb6287db78ad07a169b8d0d4e11278e950be5c37a3265a8596ab8c2ff1db154) |
| `SparkLauncherV2.setBurner(SparkBurner)` | 113278039 | [`0x26ede0...b6563b`](https://bscscan.com/tx/0x26ede0064c4638c6a83ca3e70166ec14acf44d8c48208aade0c73bdfbf36563b) |
| `SparkLauncherV2.addDex` — Uniswap v4 → `SparkHookV4` (current, correct) | 113278873 | [`0x2e8311...4b340e`](https://bscscan.com/tx/0x2e8311d630a6e17c28388b839261375322c8fa4f1710c7896b883090ad4b340e) |

## Deployed config values

- `owner` (all of `SparkLocker`, `SparkLauncherV2`, `SparkHookV4`, `SparkHookInfinity`): `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- `platformWallet` (`SparkLocker`, both hooks): `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F` (same as owner)
- `launchFeeWallet`: unset (`address(0)`) — defaults to `owner`
- `launchFee`: `0.001111 ether`
- `marketCapRef`: `5e18` (default, unchanged)
- `ctoFee` (`SparkLocker`, both hooks): `0.1 ether` (default, unchanged)
- `ctoFeeWallet` (`SparkLocker`, both hooks): unset (`address(0)`) — defaults to `owner`
- `SparkLocker.creatorBps` / `platformBps`: `7000` / `3000` (default, unchanged)
- `SparkHookV4.platformBps` / `SparkHookInfinity.platformBps`: `3000` (default, unchanged)

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

## Deprecated / abandoned

| Contract | Address | Status |
|---|---|---|
| `SparkHookV4` (first attempt) | `0xA399849Ef491FA2ee2A02751b6440c8d5a04c0C4` | **Do not use.** Deployed directly via a salted `new SparkHookV4{salt}()` under `vm.startBroadcast()`, which Foundry routes through the canonical CREATE2 deployer proxy (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) since a plain EOA can't execute the CREATE2 opcode itself. That made the proxy `msg.sender` inside the constructor, so `owner = msg.sender` set this hook's `owner` to the proxy contract — which has no way to call anything back. Its admin functions (`transferOwnership`, `setPlatformWallet`, `approveCTO`/`rejectCTO`, etc.) are permanently uncallable by anyone. It was briefly registered as the Uniswap v4 hook (block 113278023) and immediately superseded (block 113278873) before any token was ever launched through it — no user funds or pools were ever exposed to it. The fix (`HookV4Factory` above) deploys via CREATE2 from a contract we control instead, so it can call `transferOwnership` back to the real deployer atomically in the same transaction. |
| `SparkToken` impl (first attempt) | `0xE33c47C89e57C8C3493A257Fd1b699aa5887b43E` | **Do not use.** From an earlier `DeploySparkV2` broadcast that also hit the same public RPC's "in-flight transaction limit reached for delegated accounts" error after its 4th transaction. Unrelated to the `SparkHookV4` bug above — just the same rate limit hit twice, ~3 minutes apart, on two separate full-script attempts. |
| `SparkLocker` (first attempt) | `0xFA7aB74FdC8fD10E792Ee0Bc4Cd6fd34e439AC08` | **Do not use.** Paired with the abandoned token impl and launcher above; `setLauncher` was called on it, but nothing else. |
| `SparkLauncherV2` (first attempt) | `0x494BD7CA07Ce1FFDF4CAaCf117B30dF29e48c742` | **Do not use.** No hook or burner was ever configured on this instance — `dexes(V4_POSITION_MANAGER).hook == address(0)`, so `launch()` unconditionally reverts (`HookRequired`) on it. Structurally inert; safe to ignore. |

## Reproducing this deployment

Scripts live in [`deploy/`](deploy/) (a separate Foundry project, gitignored `lib/`/`out/`/`cache/`):

- `script/DeploySparkV2.s.sol` — full from-scratch deployment (token impl, locker, launcher, both hooks, burner, all wiring).
- `script/HookV4Factory.sol` + `script/FixSparkHookV4.s.sol` — the CREATE2-via-proxy ownership fix pattern for `SparkHookV4` specifically; reusable if a hook ever needs redeploying.
