// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Deploys SparkCF on BSC: fresh SparkCFToken impl, a dedicated SparkLocker
// instance (used only by the 0%-tax V3 path), and the upgradeable
// SparkCFLauncher behind a UUPS proxy. PancakeSwap V3 (1% tier) for tax-free
// tokens, PancakeSwap V2 for taxed tokens (LP burned at seed time). Also
// configures both TWAP goal-pricing sources — the deepest real WBNB/USDT
// pools on each protocol, confirmed on-chain (getPool/getPair + liquidity/
// reserves) before use, not assumed — and the dexQuoteAsset swap-at-finalize
// routes for every quote token already live on SparkLauncher/SparkGo on this
// chain (see Deployment.md), reusing the exact same route shapes.

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SparkCFToken} from "spark-cf-contracts/SparkCFToken.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkCFLauncher} from "spark-cf-contracts/SparkCFLauncher.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";

contract DeploySparkCFBSC is Script {
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address constant USD1 = 0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d;

    address constant AAPLB   = 0x431a3BEE82E2ca41e49895CbECE5bB0F76A89b7A;
    address constant NVDAB   = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;
    address constant TSLAB   = 0x5b1910eAaD6450E50f816082Aa078C41F10C292f;
    address constant SPCXB   = 0xbe9D156892E55e7154BcD3cB0FEA677F9D3103E1;
    address constant ONECOIN = 0xe43eF1fE041Ba9E8da87E8C5bFD583B3b46A1111;

    address constant PANCAKE_V3_FACTORY          = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address constant PANCAKE_V3_POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address constant PANCAKE_V3_SMART_ROUTER     = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    address constant UNISWAP_V3_SWAP_ROUTER02    = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;
    address constant PANCAKE_V2_ROUTER           = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // Deepest real WBNB/USDT pools on each protocol, confirmed on-chain before use.
    address constant WBNB_USDT_V3_POOL = 0x172fcD41E0913e95784454622d1c3724f546f849; // fee=100
    address constant WBNB_USDT_V2_PAIR = 0x16b9a82891338f9bA80E2D6970FddA79D1eb0daE;
    uint8   constant USDT_DECIMALS_BSC = 18;
    uint32  constant TWAP_WINDOW = 1800;

    uint256 constant CAMPAIGN_FEE = 0.001111 ether;
    uint256 constant TX_DELAY_MS = 10000;

    function run() external returns (address launcherProxy) {
        vm.startBroadcast();
        address deployer = msg.sender;

        SparkCFToken tokenImpl = new SparkCFToken();
        console2.log("SparkCFToken impl    :", address(tokenImpl));
        vm.sleep(TX_DELAY_MS);

        SparkLocker locker = new SparkLocker(deployer);
        console2.log("SparkCF locker       :", address(locker));
        vm.sleep(TX_DELAY_MS);

        SparkCFLauncher impl = new SparkCFLauncher();
        console2.log("SparkCFLauncher impl :", address(impl));
        vm.sleep(TX_DELAY_MS);

        bytes memory initData = abi.encodeCall(
            SparkCFLauncher.initialize,
            (WBNB, address(tokenImpl), address(locker), PANCAKE_V3_FACTORY, PANCAKE_V3_POSITION_MANAGER,
             PANCAKE_V2_ROUTER, address(0), CAMPAIGN_FEE)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        launcherProxy = address(proxy);
        console2.log("SparkCFLauncher proxy:", launcherProxy);
        vm.sleep(TX_DELAY_MS);

        locker.setLauncher(launcherProxy);
        vm.sleep(TX_DELAY_MS);

        SparkCFLauncher launcher = SparkCFLauncher(payable(launcherProxy));
        launcher.setV3TwapSource(WBNB_USDT_V3_POOL, USDT, USDT_DECIMALS_BSC, TWAP_WINDOW);
        vm.sleep(TX_DELAY_MS);
        launcher.setV2TwapSource(WBNB_USDT_V2_PAIR, USDT, USDT_DECIMALS_BSC, TWAP_WINDOW);
        vm.sleep(TX_DELAY_MS);

        // dexQuoteAsset swap-at-finalize routes — same set and shapes already live on
        // SparkLauncher/SparkGo on BSC.
        launcher.setRoutes(USDT, _singleHop(WBNB, USDT, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(USDC, _singleHop(WBNB, USDC, 100));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(USD1, _singleHop(WBNB, USD1, 100));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(AAPLB, _routeWithFallback(AAPLB, 2500, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(NVDAB, _routeWithFallback(NVDAB, 2500, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(TSLAB, _routePancakeOnly(TSLAB, 2500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(SPCXB, _routeWithFallback(SPCXB, 2500, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(ONECOIN, _v2Route());
        vm.sleep(TX_DELAY_MS);

        vm.stopBroadcast();
    }

    function _singleHop(address tokenIn, address tokenOut, uint24 fee) private pure returns (Route[] memory routes) {
        address[] memory path = new address[](2);
        path[0] = tokenIn; path[1] = tokenOut;
        uint24[] memory fees = new uint24[](1);
        fees[0] = fee;
        routes = new Route[](1);
        routes[0] = Route({
            shape: RouteShape.V3_STYLE, enabled: true, router: PANCAKE_V3_SMART_ROUTER, routerNoDeadline: true,
            path: path, fees: fees, routers: new address[](0), singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
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

    // 1COIN's only real liquidity is a thin PancakeSwap V2 pool.
    function _v2Route() private pure returns (Route[] memory routes) {
        address[] memory path = new address[](2);
        path[0] = WBNB; path[1] = ONECOIN;
        routes = new Route[](1);
        routes[0] = Route({
            shape: RouteShape.V2_STYLE, enabled: true, router: PANCAKE_V2_ROUTER, routerNoDeadline: false,
            path: path, fees: new uint24[](0), routers: new address[](0), singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
    }
}
