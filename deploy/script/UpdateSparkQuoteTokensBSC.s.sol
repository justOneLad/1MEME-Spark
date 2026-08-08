// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Owner-only config update on BSC: raises WBNB/native marketCapRef to a
// $2,000 reference, and registers 1COIN at a $1,500 reference. 1COIN's only
// liquidity is a thin PancakeSwap V2 pool (total supply is 1 token) — real
// but shallow, so instant-buy through it hits slippage limits fast.

import {Script, console2} from "forge-std/Script.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";

contract UpdateSparkQuoteTokensBSC is Script {
    address constant SPARK_LAUNCHER_PROXY = 0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973;
    address constant SPARKGO_PROXY        = 0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C;

    address constant WBNB       = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant ONECOIN    = 0xe43eF1fE041Ba9E8da87E8C5bFD583B3b46A1111;
    address constant CAKE_V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    uint256 constant WBNB_REF_2000USD    = 3373477718179671040;  // ~3.373 BNB at deploy-time price
    uint256 constant ONECOIN_REF_1500USD = 65296615894672392;    // ~0.0653 1COIN at deploy-time price

    uint256 constant TX_DELAY_MS = 10000;

    function run() external {
        vm.startBroadcast();

        SparkLauncher launcher = SparkLauncher(payable(SPARK_LAUNCHER_PROXY));
        SparkGoLauncher goLauncher = SparkGoLauncher(payable(SPARKGO_PROXY));

        launcher.setMarketCapRef(WBNB, WBNB_REF_2000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(address(0), WBNB_REF_2000USD);
        vm.sleep(TX_DELAY_MS);

        launcher.addQuoteToken(ONECOIN, ONECOIN_REF_1500USD, 0);
        vm.sleep(TX_DELAY_MS);
        goLauncher.addQuoteToken(ONECOIN, ONECOIN_REF_1500USD);
        vm.sleep(TX_DELAY_MS);

        launcher.setRoutes(ONECOIN, _v2Route());
        vm.sleep(TX_DELAY_MS);
        goLauncher.setRoutes(ONECOIN, _v2Route());
        vm.sleep(TX_DELAY_MS);

        vm.stopBroadcast();
    }

    function _v2Route() private pure returns (Route[] memory routes) {
        address[] memory path = new address[](2);
        path[0] = WBNB; path[1] = ONECOIN;
        routes = new Route[](1);
        routes[0] = Route({
            shape: RouteShape.V2_STYLE, enabled: true, router: CAKE_V2_ROUTER, routerNoDeadline: false,
            path: path, fees: new uint24[](0), routers: new address[](0), singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
    }
}
