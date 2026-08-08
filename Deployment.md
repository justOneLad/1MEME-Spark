# Spark — Mainnet Deployments

Two independent, UUPS-upgradeable launcher families are live on both BSC and
Ethereum mainnet: **SparkLauncher** (plain Uniswap V3 / PancakeSwap V3 pools)
and **SparkGo** (hook-gated Uniswap v4 / PancakeSwap Infinity singleton
pools). Both share a bounded-fallback instant-buy routing engine
(`common/SparkRouting.sol`) that supports arbitrary quote tokens and can
chain hops across different DEXs in a single route. All contracts below are
verified on the relevant explorer, proxies linked to their implementations.

Every platform/CTO/campaign fee wallet across both chains (`SparkLocker`
platform + CTO fees, SparkGo hook platform + CTO fees, `MerkleDistributor`
campaign fees) is set to the platform multisig
`0x56e6A19fF30bB4d91926e4Acf03E1CFaB2cE36d0`. `launchFeeWallet` on both
launchers is separate and unset (defaults to `owner`).

## BSC (chain `56`)

### Shared contracts

| Contract | Address |
|---|---|
| `SparkToken` (implementation, used by both launchers) | [`0xeC2cd8Ad351D3fE8948bF973471ACA2b3987CfAA`](https://bscscan.com/address/0xeC2cd8Ad351D3fE8948bF973471ACA2b3987CfAA#code) |
| `SparkLocker` (SparkLauncher's) | [`0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86`](https://bscscan.com/address/0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86#code) |
| `SparkLocker` (SparkGo's) | [`0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B`](https://bscscan.com/address/0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B#code) |

`SparkToken` antibot: max wallet 3% of supply for 30 minutes after launch, unrestricted after.

### SparkLauncher

| Contract | Address |
|---|---|
| Implementation | [`0x26aB192d831056b52B730c8e1665568DED571524`](https://bscscan.com/address/0x26aB192d831056b52B730c8e1665568DED571524#code) |
| **Proxy — use this address** | [`0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973`](https://bscscan.com/address/0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: PancakeSwap V3 (Factory `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865`, SmartRouter `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4`) and Uniswap V3 (Factory `0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7`, SwapRouter02 `0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2`), both `routerNoDeadline: true`
- `launchFee`: `0.001111 ether`
- Quote tokens (`marketCapRef`, all 18-decimal): WBNB `3.373e18` (≈$2,000) · USDT/USDC/USD1 `2000e18` each · AAPLB `6.395e18` · NVDAB `8.956e18` · TSLAB `6.071e18` · SPCXB `14.986e18` (all ≈$2,000 launch market cap, Binance bStocks) · 1COIN (`0xe43eF1fE041Ba9E8da87E8C5bFD583B3b46A1111`) `0.0653e18` (≈$1,500)
- Routes: single-hop PancakeSwap for stables, two-route fallback (PancakeSwap V3 primary, Uniswap V3 fallback) for AAPLB/NVDAB/SPCXB, PancakeSwap-only for TSLAB (no Uniswap liquidity), single-hop PancakeSwap V2 for 1COIN (its only liquidity — a thin pool, since 1COIN's total supply is 1 token; instant-buy through it hits slippage limits fast)

### SparkGo

| Contract | Address |
|---|---|
| Implementation | [`0xDD5871DC938dE998a89b96A69cF633347f93F1B8`](https://bscscan.com/address/0xDD5871DC938dE998a89b96A69cF633347f93F1B8#code) |
| **Proxy — use this address** | [`0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C`](https://bscscan.com/address/0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C#code) |
| `SparkGoHookV4` | [`0x5bA7D23C085418fd44B971726e60d4864c8400c4`](https://bscscan.com/address/0x5bA7D23C085418fd44B971726e60d4864c8400c4#code) |
| `SparkGoHookInfinity` | [`0x05AAb89F069DFAe5723DaF7c8dC21995f37729Dc`](https://bscscan.com/address/0x05AAb89F069DFAe5723DaF7c8dC21995f37729Dc#code) |
| `SparkGoBurner` | [`0xC99fD815f5C0a5dCf2B6cA36A38AbbB5cF4e4c10`](https://bscscan.com/address/0xC99fD815f5C0a5dCf2B6cA36A38AbbB5cF4e4c10#code) |
| `SparkGoHookFactory` (one-time deploy helper) | [`0x938590Efa1B08b0651cA0eA138801d6D73771D91`](https://bscscan.com/address/0x938590Efa1B08b0651cA0eA138801d6D73771D91#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: Uniswap v4 → `SparkGoHookV4`, PancakeSwap Infinity → `SparkGoHookInfinity`
- `launchFee`: `0.001111 ether`, `burner`: `SparkGoBurner` above
- Quote tokens/routes: same set and values as SparkLauncher above (including 1COIN), native BNB (`address(0)`, `marketCapRef` `3.373e18`, ≈$2,000)
- Hooks enforce same-block re-entry protection only (no buy-size cap) during the 30-minute antibot window; `SparkToken`'s 3% max-wallet is the only size cap

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
| — | AAPLB (Binance bStock, rebasing) | `0x431a3BEE82E2ca41e49895CbECE5bB0F76A89b7A` |
| — | NVDAB (Binance bStock, rebasing) | `0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436` |
| — | TSLAB (Binance bStock, rebasing) | `0x5b1910eAaD6450E50f816082Aa078C41F10C292f` |
| — | SPCXB (Binance bStock, rebasing) | `0xbe9D156892E55e7154BcD3cB0FEA677F9D3103E1` |
| — | 1COIN (18 dec, total supply 1 token) | `0xe43eF1fE041Ba9E8da87E8C5bFD583B3b46A1111` |
| — | AAPL (Ondo Tokenized, disabled — dead route) | `0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4` |
| — | NVDA (Ondo Tokenized, disabled) | `0xA9eE28C80f960B889dFbd1902055218cBa016F75` |
| — | TSLA (Ondo Tokenized, disabled — zero liquidity) | `0x2494b603319d4D9F9715c9f4496d9E0364B59d93` |
| — | SPCX (Ondo Tokenized, disabled) | `0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928` |

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
| `SparkToken` (implementation, used by both launchers) | [`0x99ff75d2da25ac4cB0C5ea88c31EFEfDa64FCCb1`](https://etherscan.io/address/0x99ff75d2da25ac4cB0C5ea88c31EFEfDa64FCCb1#code) |
| `SparkLocker` (SparkLauncher's) | [`0x2C238982945d5bE37dc6cFDFDD0c942458326C32`](https://etherscan.io/address/0x2C238982945d5bE37dc6cFDFDD0c942458326C32#code) |
| `SparkLocker` (SparkGo's) | [`0x541b04c5389E540bcc875EA14F699E539f96F76A`](https://etherscan.io/address/0x541b04c5389E540bcc875EA14F699E539f96F76A#code) |

`SparkToken` antibot: max wallet 3% of supply for 30 minutes after launch, unrestricted after.

### SparkLauncher

| Contract | Address |
|---|---|
| Implementation | [`0x6E307660e9366Eb7ECd8686cEa0dA2C012aD6c1c`](https://etherscan.io/address/0x6E307660e9366Eb7ECd8686cEa0dA2C012aD6c1c#code) |
| **Proxy — use this address** | [`0x1010B4593376A5eEc045F9A706F615ed8417f541`](https://etherscan.io/address/0x1010B4593376A5eEc045F9A706F615ed8417f541#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: PancakeSwap V3 (Factory `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865`, SmartRouter `0x13f4EA83D0bd40E75C8222255bc855a974568Dd4`) and Uniswap V3 (Factory `0x1F98431c8aD98523631AE4a59f267346ea31F984`, SwapRouter02 `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45`), both `routerNoDeadline: true`
- `launchFee`: `0.001111 ether`
- Quote tokens (`marketCapRef`): WETH `5e18` (default) · USDT/USDC `2_000_000000` each (6-decimal, $2,000) · AAPL `6.497e18` · NVDA `9.729e18` · TSLA `6.286e18` · SPCX `19.784e18` (stocks all 18-decimal, ≈$2,000 launch market cap)
- Routes: single-hop Uniswap V3 for USDT (fee 0.3%)/USDC (fee 0.05%); multi-hop WETH→USDC→stock via Uniswap V3 for AAPL (fee 0.3%)/NVDA/TSLA/SPCX (fee 1% each) — PancakeSwap has no real liquidity for these pairs on Ethereum, so everything routes through Uniswap

### SparkGo

| Contract | Address |
|---|---|
| Implementation | [`0x605afabfD2C87117EC1BDe8A01F1D9aF3195F785`](https://etherscan.io/address/0x605afabfD2C87117EC1BDe8A01F1D9aF3195F785#code) |
| **Proxy — use this address** | [`0x1655d6d3D2A6a29cf17bC151eDeA50A14A5DC918`](https://etherscan.io/address/0x1655d6d3D2A6a29cf17bC151eDeA50A14A5DC918#code) |
| `SparkGoHookV4` | [`0x331CC61E71249Ba26E591A2b2ee563F588d980C4`](https://etherscan.io/address/0x331CC61E71249Ba26E591A2b2ee563F588d980C4#code) |
| `SparkGoBurner` | [`0x125Fd8e0BC3cfbe913C65bB2Ba93d7eA9372982c`](https://etherscan.io/address/0x125Fd8e0BC3cfbe913C65bB2Ba93d7eA9372982c#code) |
| `SparkGoHookFactory` (one-time deploy helper) | [`0xbE9dFD8E5e26baAF2bC44914dEB83051a61096c2`](https://etherscan.io/address/0xbE9dFD8E5e26baAF2bC44914dEB83051a61096c2#code) |

- `owner`: `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F`
- DEXs: Uniswap v4 → `SparkGoHookV4` only (no PancakeSwap Infinity on Ethereum)
- `launchFee`: `0.001111 ether`, `burner`: `SparkGoBurner` above
- Quote tokens/routes: same set and values as SparkLauncher above, plus native ETH (`address(0)`, `marketCapRef` `5e18`)
- Hook enforces same-block re-entry protection only (no buy-size cap) during the 30-minute antibot window; `SparkToken`'s 3% max-wallet is the only size cap

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

---

## Distributors

Independent, protocol-agnostic — no relation to any Spark launcher. Live on
both chains with identical addresses' *behavior* (not the same address; each
was a separate deploy).

| Contract | BSC | Ethereum |
|---|---|---|
| `MultiSender` | [`0xca1D1e81B328fE0977de845c8D5226F84331Ac09`](https://bscscan.com/address/0xca1D1e81B328fE0977de845c8D5226F84331Ac09#code) | [`0x1500CAae3e4E56C680bbd0428749b32a814ea4c7`](https://etherscan.io/address/0x1500CAae3e4E56C680bbd0428749b32a814ea4c7#code) |
| `MerkleDistributor` (implementation) | [`0x24097aDd152f0614cfE9eb841721d6a7D20A574d`](https://bscscan.com/address/0x24097aDd152f0614cfE9eb841721d6a7D20A574d#code) | [`0x773371fD25a57B503596d361491929250c372890`](https://etherscan.io/address/0x773371fD25a57B503596d361491929250c372890#code) |
| `MerkleDistributor` (proxy — use this address) | [`0x20ED1b487dd2A172D5ba0ED33562370142Cc338b`](https://bscscan.com/address/0x20ED1b487dd2A172D5ba0ED33562370142Cc338b#code) | [`0xcB3ccF9f74c08A70b2B1bf7c111391d158D18B1c`](https://etherscan.io/address/0xcB3ccF9f74c08A70b2B1bf7c111391d158D18B1c#code) |

`MerkleDistributor`: `owner` `0x46cfAd847B0e630d65C01EcdA684ff2326b9f71F` on both chains,
`campaignFee` `0.001111 ether` (native, charged on every `createCampaign` regardless
of caller — funds the platform's indexing/API work for surfacing campaigns),
`feeWallet` set to the platform multisig above. Campaign creation is permissionless;
only a campaign's own `creator` can `sweep` its unclaimed remainder after its
deadline — the platform's only claim on any campaign is the upfront fee.
