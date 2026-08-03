# Spark — Mainnet Deployments

Two independent, UUPS-upgradeable launcher families are live on both BSC and
Ethereum mainnet: **SparkLauncher** (plain Uniswap V3 / PancakeSwap V3 pools)
and **SparkGo** (hook-gated Uniswap v4 / PancakeSwap Infinity singleton
pools). Both share a bounded-fallback instant-buy routing engine
(`common/SparkRouting.sol`) that supports arbitrary quote tokens and can
chain hops across different DEXs in a single route. All contracts below are
verified on the relevant explorer, proxies linked to their implementations.

## BSC (chain `56`)

### Shared contracts

| Contract | Address |
|---|---|
| `SparkToken` (implementation, used by both launchers) | [`0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA`](https://bscscan.com/address/0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA#code) |
| `SparkLocker` (SparkLauncher's) | [`0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86`](https://bscscan.com/address/0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86#code) |
| `SparkLocker` (SparkGo's) | [`0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B`](https://bscscan.com/address/0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B#code) |

### SparkLauncher

| Contract | Address |
|---|---|
| Implementation | [`0xE4dD59Fb5b78a5f92fCf4A42154f582A18b4f1f0`](https://bscscan.com/address/0xE4dD59Fb5b78a5f92fCf4A42154f582A18b4f1f0#code) |
| **Proxy — use this address** | [`0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973`](https://bscscan.com/address/0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: PancakeSwap V3 (Factory `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865`, SmartRouter `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4`) and Uniswap V3 (Factory `0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7`, SwapRouter02 `0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2`), both `routerNoDeadline: true`
- `launchFee`: `0.001111 ether`
- Quote tokens (`marketCapRef`, all 18-decimal): WBNB `5e18` · USDT/USDC/USD1 `2000e18` each · AAPL `6.629e18` · NVDA `10.066e18` · TSLA `4.788e18` · SPCX `18.349e18` (all ≈$2,000 launch market cap)
- Routes: single-hop PancakeSwap for stables, multi-hop (WBNB→USDT→stock) for AAPL/NVDA/TSLA, cross-DEX chained (PancakeSwap WBNB→USDT, Uniswap USDT→SPCX) for SPCX

### SparkGo

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

### External BSC dependencies

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
| — | USDT (18 dec) | `0x55d398326f99059fF775485246999027B3197955` |
| — | USDC (18 dec) | `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d` |
| — | USD1 (18 dec) | `0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d` |
| — | AAPL (Ondo Tokenized) | `0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4` |
| — | NVDA (Ondo Tokenized) | `0xA9eE28C80f960B889dFbd1902055218cBa016F75` |
| — | TSLA (Ondo Tokenized) | `0x2494b603319d4D9F9715c9f4496d9E0364B59d93` |
| — | SPCX (Ondo Tokenized) | `0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928` |

---

## Ethereum (chain `1`)

Nothing pre-existed on Ethereum to reuse, unlike BSC — `SparkToken` and both
`SparkLocker`s were deployed fresh alongside the launchers. PancakeSwap
Infinity has no Ethereum deployment, so SparkGo only registers Uniswap v4
here. Every stock's real liquidity is against USDC, not USDT — the opposite
of BSC — and **Ethereum's USDT/USDC use 6 decimals**, not BSC's 18, so
`marketCapRef` values differ in scale even where the target USD value matches.

### Shared contracts

| Contract | Address |
|---|---|
| `SparkToken` (implementation, used by both launchers) | [`0x53457519609B167CA01DCf47BD1b5998DB2C78cb`](https://etherscan.io/address/0x53457519609B167CA01DCf47BD1b5998DB2C78cb#code) |
| `SparkLocker` (SparkLauncher's) | [`0x2C238982945d5bE37dc6cFDFDD0c942458326C32`](https://etherscan.io/address/0x2C238982945d5bE37dc6cFDFDD0c942458326C32#code) |
| `SparkLocker` (SparkGo's) | [`0x541b04c5389E540bcc875EA14F699E539f96F76A`](https://etherscan.io/address/0x541b04c5389E540bcc875EA14F699E539f96F76A#code) |

### SparkLauncher

| Contract | Address |
|---|---|
| Implementation | [`0x5738FDd259254a1d2e77aB758eE4aB908b21C422`](https://etherscan.io/address/0x5738FDd259254a1d2e77aB758eE4aB908b21C422#code) |
| **Proxy — use this address** | [`0x1010B4593376A5eEc045F9A706F615ed8417f541`](https://etherscan.io/address/0x1010B4593376A5eEc045F9A706F615ed8417f541#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: PancakeSwap V3 (Factory `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865`, SmartRouter `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4`) and Uniswap V3 (Factory `0x1F98431c8aD98523631AE4a59f267346ea31F984`, SwapRouter02 `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45`), both `routerNoDeadline: true`
- `launchFee`: `0.001111 ether`
- Quote tokens (`marketCapRef`): WETH `5e18` (default) · USDT/USDC `2_000_000000` each (6-decimal, $2,000) · AAPL `6.497e18` · NVDA `9.729e18` · TSLA `6.286e18` · SPCX `19.784e18` (stocks all 18-decimal, ≈$2,000 launch market cap)
- Routes: single-hop Uniswap V3 for USDT (fee 0.3%)/USDC (fee 0.05%); multi-hop WETH→USDC→stock via Uniswap V3 for AAPL (fee 0.3%)/NVDA/TSLA/SPCX (fee 1% each) — PancakeSwap has no real liquidity for these pairs on Ethereum, so everything routes through Uniswap

### SparkGo

| Contract | Address |
|---|---|
| Implementation | [`0xcc2052A4e30DC89181Dc57261d63C0a795F21043`](https://etherscan.io/address/0xcc2052A4e30DC89181Dc57261d63C0a795F21043#code) |
| **Proxy — use this address** | [`0x1655d6d3D2A6a29cf17bC151eDeA50A14A5DC918`](https://etherscan.io/address/0x1655d6d3D2A6a29cf17bC151eDeA50A14A5DC918#code) |
| `SparkGoHookV4` | [`0x49706386e0Fb729D24947a57f50097Ac578e80c4`](https://etherscan.io/address/0x49706386e0Fb729D24947a57f50097Ac578e80c4#code) |
| `SparkGoBurner` | [`0x125Fd8e0BC3cfbe913C65bB2Ba93d7eA9372982c`](https://etherscan.io/address/0x125Fd8e0BC3cfbe913C65bB2Ba93d7eA9372982c#code) |
| `SparkGoHookFactory` (one-time deploy helper) | [`0x07d7EaACA34EBEa70d4f598A1477550366C82F15`](https://etherscan.io/address/0x07d7EaACA34EBEa70d4f598A1477550366C82F15#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: Uniswap v4 → `SparkGoHookV4` only (no PancakeSwap Infinity on Ethereum)
- `launchFee`: `0.001111 ether`, `burner`: `SparkGoBurner` above
- Quote tokens/routes: same set and values as SparkLauncher above, plus native ETH (`address(0)`, `marketCapRef` `5e18`)

### External Ethereum dependencies

| Protocol | Contract | Address |
|---|---|---|
| Uniswap v4 | PositionManager | `0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e` |
| Uniswap v4 | PoolManager | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Uniswap v4 | Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| PancakeSwap V3 | Factory | `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865` |
| PancakeSwap V3 | PositionManager | `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364` |
| PancakeSwap V3 | SmartRouter (no-deadline ABI) | `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4` |
| Uniswap V3 | Factory | `0x1F98431c8aD98523631AE4a59f267346ea31F984` |
| Uniswap V3 | PositionManager | `0xC36442b4a4522E871399CD717aBDD847Ab11FE88` |
| Uniswap V3 | SwapRouter02 (no-deadline ABI) | `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45` |
| — | WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |
| — | USDT (6 dec) | `0xdAC17F958D2ee523a2206206994597C13D831ec7` |
| — | USDC (6 dec) | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |
| — | AAPL (Ondo Tokenized) | `0x14c3abF95Cb9C93a8b82C1CdCB76D72Cb87b2d4c` |
| — | NVDA (Ondo Tokenized) | `0x2D1F7226Bd1F780AF6B9A49DCC0aE00E8Df4bDEE` |
| — | TSLA (Ondo Tokenized) | `0xf6b1117ec07684D3958caD8BEb1b302bfD21103f` |
| — | SPCX (Ondo Tokenized) | `0xc9eef266834730340A55B6CC24621B31BAF55581` |
