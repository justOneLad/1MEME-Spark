# Spark — BSC Mainnet Deployment

Chain: BNB Smart Chain (BSC) mainnet, chain ID `56`.

Two independent, UUPS-upgradeable launcher families are live: **SparkLauncher**
(plain Uniswap V3 / PancakeSwap V3 pools) and **SparkGo** (hook-gated Uniswap
v4 / PancakeSwap Infinity singleton pools). Both share a bounded-fallback
instant-buy routing engine (`common/SparkRouting.sol`) that supports
arbitrary quote tokens and can chain hops across different DEXs in a single
route — e.g. SPCX's route goes PancakeSwap (WBNB→USDT) then Uniswap
(USDT→SPCX), since no single DEX has real liquidity for both legs. All
contracts below are verified on BscScan, proxies linked to their
implementations.

## Shared contracts

| Contract | Address |
|---|---|
| `SparkToken` (implementation, used by both launchers) | [`0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA`](https://bscscan.com/address/0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA#code) |
| `SparkLocker` (SparkLauncher's) | [`0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86`](https://bscscan.com/address/0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86#code) |
| `SparkLocker` (SparkGo's) | [`0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B`](https://bscscan.com/address/0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B#code) |

## SparkLauncher

| Contract | Address |
|---|---|
| Implementation | [`0xE4dD59Fb5b78a5f92fCf4A42154f582A18b4f1f0`](https://bscscan.com/address/0xE4dD59Fb5b78a5f92fCf4A42154f582A18b4f1f0#code) |
| **Proxy — use this address** | [`0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973`](https://bscscan.com/address/0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: PancakeSwap V3 (Factory `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865`, SmartRouter `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4`) and Uniswap V3 (Factory `0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7`, SwapRouter02 `0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2`), both `routerNoDeadline: true`
- `launchFee`: `0.001111 ether`
- Quote tokens (`marketCapRef`): WBNB `5e18` · USDT/USDC/USD1 `2000e18` each · AAPL `6.629e18` · NVDA `10.066e18` · TSLA `4.788e18` · SPCX `18.349e18` (all ≈$2,000 launch market cap)
- Routes: single-hop PancakeSwap for stables, multi-hop (WBNB→USDT→stock) for AAPL/NVDA/TSLA, cross-DEX chained (PancakeSwap→Uniswap) for SPCX

## SparkGo

| Contract | Address |
|---|---|
| Implementation | [`0x8AE5052A18439D7120124AB1356b5A1cD19606A8`](https://bscscan.com/address/0x8AE5052A18439D7120124AB1356b5A1cD19606A8#code) |
| **Proxy — use this address** | [`0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C`](https://bscscan.com/address/0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C#code) |
| `SparkGoHookV4` | [`0xdF3f8b41a55fb8737D653d6bc7467095e48700c4`](https://bscscan.com/address/0xdF3f8b41a55fb8737D653d6bc7467095e48700c4#code) |
| `SparkGoHookInfinity` | [`0x8E273c882267f034ACE21dA677dBF0c0eB305B82`](https://bscscan.com/address/0x8E273c882267f034ACE21dA677dBF0c0eB305B82#code) |
| `SparkGoBurner` | [`0xC99fD815f5C0a5dCf2B6cA36A38AbbB5cF4e4c10`](https://bscscan.com/address/0xC99fD815f5C0a5dCf2B6cA36A38AbbB5cF4e4c10#code) |
| `SparkGoHookFactory` (one-time deploy helper) | [`0xF3DF835378eC75346b66b7821e501ebAf535Fa16`](https://bscscan.com/address/0xF3DF835378eC75346b66b7821e501ebAf535Fa16#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: Uniswap v4 → `SparkGoHookV4`, PancakeSwap Infinity → `SparkGoHookInfinity`
- `launchFee`: `0.001111 ether`, `burner`: `SparkGoBurner` above
- Quote tokens/routes: same set and values as SparkLauncher above, plus native BNB (`address(0)`, `marketCapRef` `5e18`)

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

## Reproducing this deployment

Scripts live in [`deploy/`](deploy/) (a separate Foundry project;
`forge install OpenZeppelin/openzeppelin-contracts-upgradeable` needed before
building). `deploy/test/` has a fork-test suite (`vm.createSelectFork`
against live BSC state, not testnet) — 13/13 passing.

```
./deploy-all.sh <private-key> [rpc-url]   # runs both scripts, --skip-simulation baked in
```

Most public/shared BSC RPC endpoints (`bsc-dataseed.binance.org`,
`bsc.publicnode.com`, GetBlock's shared tier) can't complete a `--broadcast`
run — `forge script` always simulates once successfully, then fails a second
on-chain verification pass with "missing trie node" / archive-request errors.
`--skip-simulation` (broadcast directly from the first pass) fixes it;
`binance.nodereal.io` has proven reliable end-to-end. Some free tiers also
gate `eth_getTransactionReceipt` mid-sequence even after a transaction
succeeds — verify on-chain state directly (`cast call`) before assuming a
failure report means a transaction didn't land.
