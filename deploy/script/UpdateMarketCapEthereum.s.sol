// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Owner-only config update on Ethereum: drops every quote token's
// marketCapRef on SparkLauncher/SparkGo, and SparkCF's usdGoalTarget18, from
// ~$2,000/$3,000 to a $1,000 reference. Each marketCapRef below was computed
// from a live on-chain price read (Uniswap V3 pools for WETH/AAPL/NVDA/
// TSLA/SPCX against USDC) at broadcast time, not a stale/assumed figure.

import {Script, console2} from "forge-std/Script.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {SparkCFLauncher} from "spark-cf-contracts/SparkCFLauncher.sol";

contract UpdateMarketCapEthereum is Script {
    address constant SPARK_LAUNCHER_PROXY = 0x1010B4593376A5eEc045F9A706F615ed8417f541;
    address constant SPARKGO_PROXY        = 0x1655d6d3D2A6a29cf17bC151eDeA50A14A5DC918;
    address constant SPARKCF_PROXY        = 0x10176E4F7A68B66a6aCeb604dCadbcc63CbE6ABB;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant AAPL = 0x14c3abF95Cb9C93a8b82C1CdCB76D72Cb87b2d4c;
    address constant NVDA = 0x2D1F7226Bd1F780AF6B9A49DCC0aE00E8Df4bDEE;
    address constant TSLA = 0xf6b1117ec07684D3958caD8BEb1b302bfD21103f;
    address constant SPCX = 0xc9eef266834730340A55B6CC24621B31BAF55581;

    uint256 constant WETH_REF_1000USD   = 405110100402617792;   // ~0.4051 ETH @ $2,468.46
    uint256 constant AAPL_REF_1000USD   = 3188970894486061568;  // ~3.189 AAPL @ $313.58
    uint256 constant NVDA_REF_1000USD   = 4835641241848115200;  // ~4.836 NVDA @ $206.80
    uint256 constant TSLA_REF_1000USD   = 2863570261513187840;  // ~2.864 TSLA @ $349.21
    uint256 constant SPCX_REF_1000USD   = 7174016156975512576;  // ~7.174 SPCX @ $139.39
    uint256 constant STABLE_REF_1000USD = 1_000_000000;         // USDT/USDC, 6-decimal $1 pegs

    uint256 constant TX_DELAY_MS = 10000;

    function run() external {
        vm.startBroadcast();

        SparkLauncher launcher = SparkLauncher(payable(SPARK_LAUNCHER_PROXY));
        SparkGoLauncher goLauncher = SparkGoLauncher(payable(SPARKGO_PROXY));
        SparkCFLauncher cfLauncher = SparkCFLauncher(payable(SPARKCF_PROXY));

        launcher.setMarketCapRef(WETH, WETH_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(USDT, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(USDC, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(AAPL, AAPL_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(NVDA, NVDA_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(TSLA, TSLA_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(SPCX, SPCX_REF_1000USD);
        vm.sleep(TX_DELAY_MS);

        goLauncher.setMarketCapRef(address(0), WETH_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(USDT, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(USDC, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(AAPL, AAPL_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(NVDA, NVDA_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(TSLA, TSLA_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(SPCX, SPCX_REF_1000USD);
        vm.sleep(TX_DELAY_MS);

        cfLauncher.setUsdGoalTarget(1000e18);
        vm.sleep(TX_DELAY_MS);

        vm.stopBroadcast();
    }
}
