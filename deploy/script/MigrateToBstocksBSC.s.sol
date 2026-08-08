// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Owner-only config update on BSC: drops the Ondo AAPL/NVDA/TSLA/SPCX quote
// tokens (AAPL/TSLA routes had gone dead; NVDA/SPCX swapped for consistency)
// for Binance's bStocks equivalents — deep, accurately-priced liquidity on
// PancakeSwap V3 (~0.2% of CoinGecko). AAPLB/NVDAB/SPCXB also fall back to
// Uniswap V3; TSLAB has no Uniswap liquidity, so it's PancakeSwap-only.
//
// bStocks are rebasing (balanceOf/balanceOfUI, totalSupply/totalSupplyUI) —
// risk accepted knowingly, see Deployment.md.

import {Script, console2} from "forge-std/Script.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";

contract MigrateToBstocksBSC is Script {
    address constant SPARK_LAUNCHER_PROXY = 0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973;
    address constant SPARKGO_PROXY        = 0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C;

    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    address constant PANCAKE_V3_SMART_ROUTER  = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    address constant UNISWAP_V3_SWAP_ROUTER02 = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;

    address constant AAPL_ONDO = 0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4;
    address constant NVDA_ONDO = 0xA9eE28C80f960B889dFbd1902055218cBa016F75;
    address constant TSLA_ONDO = 0x2494b603319d4D9F9715c9f4496d9E0364B59d93;
    address constant SPCX_ONDO = 0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928;

    address constant AAPLB = 0x431a3BEE82E2ca41e49895CbECE5bB0F76A89b7A;
    address constant NVDAB = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;
    address constant TSLAB = 0x5b1910eAaD6450E50f816082Aa078C41F10C292f;
    address constant SPCXB = 0xbe9D156892E55e7154BcD3cB0FEA677F9D3103E1;

    uint256 constant AAPLB_REF_2000USD = 6395036694267255808;
    uint256 constant NVDAB_REF_2000USD = 8956063040672935936;
    uint256 constant TSLAB_REF_2000USD = 6070553119980968960;
    uint256 constant SPCXB_REF_2000USD = 14986149749944324096;

    uint256 constant TX_DELAY_MS = 10000;

    function run() external {
        vm.startBroadcast();

        SparkLauncher launcher = SparkLauncher(payable(SPARK_LAUNCHER_PROXY));
        SparkGoLauncher goLauncher = SparkGoLauncher(payable(SPARKGO_PROXY));

        launcher.disableQuoteToken(AAPL_ONDO);
        vm.sleep(TX_DELAY_MS);
        launcher.disableQuoteToken(NVDA_ONDO);
        vm.sleep(TX_DELAY_MS);
        launcher.disableQuoteToken(TSLA_ONDO);
        vm.sleep(TX_DELAY_MS);
        launcher.disableQuoteToken(SPCX_ONDO);
        vm.sleep(TX_DELAY_MS);

        goLauncher.disableQuoteToken(AAPL_ONDO);
        vm.sleep(TX_DELAY_MS);
        goLauncher.disableQuoteToken(NVDA_ONDO);
        vm.sleep(TX_DELAY_MS);
        goLauncher.disableQuoteToken(TSLA_ONDO);
        vm.sleep(TX_DELAY_MS);
        goLauncher.disableQuoteToken(SPCX_ONDO);
        vm.sleep(TX_DELAY_MS);

        launcher.addQuoteToken(AAPLB, AAPLB_REF_2000USD, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(NVDAB, NVDAB_REF_2000USD, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(TSLAB, TSLAB_REF_2000USD, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(SPCXB, SPCXB_REF_2000USD, 0);
        vm.sleep(TX_DELAY_MS);

        goLauncher.addQuoteToken(AAPLB, AAPLB_REF_2000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.addQuoteToken(NVDAB, NVDAB_REF_2000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.addQuoteToken(TSLAB, TSLAB_REF_2000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.addQuoteToken(SPCXB, SPCXB_REF_2000USD);
        vm.sleep(TX_DELAY_MS);

        launcher.setRoutes(AAPLB, _routeWithFallback(AAPLB, 2500, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(NVDAB, _routeWithFallback(NVDAB, 2500, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(TSLAB, _routePancakeOnly(TSLAB, 2500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(SPCXB, _routeWithFallback(SPCXB, 2500, 500));
        vm.sleep(TX_DELAY_MS);

        goLauncher.setRoutes(AAPLB, _routeWithFallback(AAPLB, 2500, 500));
        vm.sleep(TX_DELAY_MS);
        goLauncher.setRoutes(NVDAB, _routeWithFallback(NVDAB, 2500, 500));
        vm.sleep(TX_DELAY_MS);
        goLauncher.setRoutes(TSLAB, _routePancakeOnly(TSLAB, 2500));
        vm.sleep(TX_DELAY_MS);
        goLauncher.setRoutes(SPCXB, _routeWithFallback(SPCXB, 2500, 500));
        vm.sleep(TX_DELAY_MS);

        vm.stopBroadcast();
    }

    function _routePancakeOnly(address stock, uint24 cakeFee) private pure returns (Route[] memory routes) {
        routes = new Route[](1);
        routes[0] = _hop(PANCAKE_V3_SMART_ROUTER, stock, 500, cakeFee);
    }

    function _routeWithFallback(address stock, uint24 cakeFee, uint24 uniFee) private pure returns (Route[] memory routes) {
        routes = new Route[](2);
        routes[0] = _hop(PANCAKE_V3_SMART_ROUTER, stock, 500, cakeFee);
        routes[1] = _hop(UNISWAP_V3_SWAP_ROUTER02, stock, 500, uniFee);
    }

    function _hop(address router, address stock, uint24 wbnbUsdtFee, uint24 usdtStockFee) private pure returns (Route memory) {
        address[] memory path = new address[](3);
        path[0] = WBNB; path[1] = USDT; path[2] = stock;
        uint24[] memory fees = new uint24[](2);
        fees[0] = wbnbUsdtFee; fees[1] = usdtStockFee;
        return Route({
            shape: RouteShape.V3_STYLE, enabled: true, router: router, routerNoDeadline: true,
            path: path, fees: fees, routers: new address[](0), singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
    }
}
