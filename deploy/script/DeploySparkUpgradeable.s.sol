// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Deploys the upgradeable SparkLauncher behind a UUPS proxy and repoints the
// existing SparkLocker at it via setLauncher. See Deployment.md for live
// addresses.

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";

contract DeploySparkUpgradeable is Script {
    address constant EXISTING_TOKEN_IMPL = 0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA;
    address constant EXISTING_LOCKER     = 0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86;

    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address constant USD1 = 0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d;

    address constant AAPL = 0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4;
    address constant NVDA = 0xA9eE28C80f960B889dFbd1902055218cBa016F75;
    address constant TSLA = 0x2494b603319d4D9F9715c9f4496d9E0364B59d93;
    address constant SPCX = 0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928;

    address constant PANCAKE_V3_FACTORY          = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address constant PANCAKE_V3_POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address constant PANCAKE_V3_SMART_ROUTER     = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;

    address constant UNISWAP_V3_FACTORY          = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
    address constant UNISWAP_V3_POSITION_MANAGER = 0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613;
    address constant UNISWAP_V3_SWAP_ROUTER02    = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;

    uint256 constant LAUNCH_FEE = 0.001111 ether;
    uint256 constant TX_DELAY_MS = 5000;

    function run() external returns (address launcherProxy) {
        vm.startBroadcast();

        SparkLauncher impl = new SparkLauncher();
        console2.log("SparkLauncher impl  :", address(impl));
        vm.sleep(TX_DELAY_MS);

        bytes memory initData = abi.encodeCall(
            SparkLauncher.initialize,
            (WBNB, EXISTING_TOKEN_IMPL, EXISTING_LOCKER, address(0), PANCAKE_V3_FACTORY, PANCAKE_V3_POSITION_MANAGER, PANCAKE_V3_SMART_ROUTER, true, LAUNCH_FEE)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        launcherProxy = address(proxy);
        console2.log("SparkLauncher proxy :", launcherProxy);
        vm.sleep(TX_DELAY_MS);

        SparkLauncher launcher = SparkLauncher(payable(launcherProxy));

        SparkLocker(EXISTING_LOCKER).setLauncher(launcherProxy);
        vm.sleep(TX_DELAY_MS);
        launcher.addDex(UNISWAP_V3_FACTORY, UNISWAP_V3_POSITION_MANAGER, UNISWAP_V3_SWAP_ROUTER02, true);
        vm.sleep(TX_DELAY_MS);

        launcher.addQuoteToken(USDT, 2000 ether, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(USDC, 2000 ether, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(USD1, 2000 ether, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(AAPL, 6629321488945606656, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(NVDA, 10066438494060800000, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(TSLA, 4788469365767232512, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(SPCX, 18348623853211009024, 0);
        vm.sleep(TX_DELAY_MS);

        launcher.setRoutes(USDT, _singleHop(WBNB, USDT, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(USDC, _singleHop(WBNB, USDC, 100));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(USD1, _singleHop(WBNB, USD1, 100));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(AAPL, _multiHop(WBNB, USDT, AAPL, 500, 100));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(NVDA, _multiHop(WBNB, USDT, NVDA, 500, 10_000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(TSLA, _multiHop(WBNB, USDT, TSLA, 500, 2_500));
        vm.sleep(TX_DELAY_MS);

        address[] memory spcxHopRouters = new address[](2);
        spcxHopRouters[0] = PANCAKE_V3_SMART_ROUTER;   // WBNB -> USDT: deepest liquidity on PancakeSwap
        spcxHopRouters[1] = UNISWAP_V3_SWAP_ROUTER02;   // USDT -> SPCX: only real liquidity is on Uniswap
        launcher.setRoutes(SPCX, _chainedMultiHop(spcxHopRouters, WBNB, USDT, SPCX, 500, 10_000));
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

    function _multiHop(address tokenIn, address mid, address tokenOut, uint24 fee0, uint24 fee1) private pure returns (Route[] memory routes) {
        return _multiHopOn(PANCAKE_V3_SMART_ROUTER, tokenIn, mid, tokenOut, fee0, fee1);
    }

    function _multiHopOn(address router, address tokenIn, address mid, address tokenOut, uint24 fee0, uint24 fee1) private pure returns (Route[] memory routes) {
        address[] memory path = new address[](3);
        path[0] = tokenIn; path[1] = mid; path[2] = tokenOut;
        uint24[] memory fees = new uint24[](2);
        fees[0] = fee0; fees[1] = fee1;
        routes = new Route[](1);
        routes[0] = Route({
            shape: RouteShape.V3_STYLE, enabled: true, router: router, routerNoDeadline: true,
            path: path, fees: fees, routers: new address[](0), singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
    }

    // Each hop can use a different router — hopRouters[i] handles path[i] -> path[i+1] — so a
    // quote token pairing only reachable across two different DEXs still works in one route.
    function _chainedMultiHop(address[] memory hopRouters, address tokenIn, address mid, address tokenOut, uint24 fee0, uint24 fee1) private pure returns (Route[] memory routes) {
        address[] memory path = new address[](3);
        path[0] = tokenIn; path[1] = mid; path[2] = tokenOut;
        uint24[] memory fees = new uint24[](2);
        fees[0] = fee0; fees[1] = fee1;
        routes = new Route[](1);
        routes[0] = Route({
            shape: RouteShape.V3_STYLE, enabled: true, router: address(0), routerNoDeadline: true,
            path: path, fees: fees, routers: hopRouters, singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
    }
}
