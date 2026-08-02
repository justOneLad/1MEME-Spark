// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Deploys the upgradeable, currency-general SparkGoLauncher behind a UUPS
// proxy, plus fresh (non-upgradeable, by design — see SparkGoHookV4.sol's
// header comment) hooks and burner. Repoints the existing SparkLocker
// (0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B, still holding the STOCKS/
// NOINTERNET positions from the old SparkLauncherV2) at the new launcher via
// setLauncher — safe for the same reason as DeploySparkUpgradeable.s.sol: the
// gate only affects new position registration, not existing fee claims.
//
// SparkGoHookV4 is deployed via SparkGoHookFactory, same CREATE2-ownership
// pattern as the original HookV4Factory (see that contract's header comment
// for why a direct salted `new` from a broadcasting EOA can't be used).

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {SparkGoHookV4} from "spark-go-contracts/hooks/SparkGoHookV4.sol";
import {SparkGoHookInfinity} from "spark-go-contracts/hooks/SparkGoHookInfinity.sol";
import {SparkGoBurner} from "spark-go-contracts/SparkGoBurner.sol";
import {SparkGoHookFactory} from "./SparkGoHookFactory.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";

contract DeploySparkGo is Script {
    address constant EXISTING_TOKEN_IMPL = 0x3df1f46498A95215fBdfaF349e9ac3Ac39DeEDbA;
    address constant EXISTING_LOCKER     = 0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B;

    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address constant USD1 = 0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d;

    address constant AAPL = 0x390a684EF9cADE28A7AD0DFa61AB1Eb3842618c4;
    address constant NVDA = 0xA9eE28C80f960B889dFbd1902055218cBa016F75;
    address constant TSLA = 0x2494b603319d4D9F9715c9f4496d9E0364B59d93;
    address constant SPCX = 0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928;

    address constant V4_POSITION_MANAGER = 0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b;
    address constant V4_POOL_MANAGER     = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant V4_PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant INF_POSITION_MANAGER = 0x55f4c8abA71A1e923edC303eb4fEfF14608cC226;
    address constant INF_VAULT            = 0x238a358808379702088667322f80aC48bAd5e6c4;
    address constant INF_CL_POOL_MANAGER  = 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b;
    address constant INF_PERMIT2          = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;

    address constant PANCAKE_V3_SMART_ROUTER  = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    address constant UNISWAP_V3_SWAP_ROUTER02 = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;

    uint256 constant LAUNCH_FEE = 0.001111 ether;
    uint256 constant TX_DELAY_MS = 5000;

    function run() external returns (
        address launcherProxy,
        address hookV4,
        address hookInfinity,
        address burner
    ) {
        vm.startBroadcast();
        address deployer = msg.sender;

        SparkGoLauncher impl = new SparkGoLauncher();
        console2.log("SparkGoLauncher impl  :", address(impl));
        vm.sleep(TX_DELAY_MS);

        bytes memory initData = abi.encodeCall(
            SparkGoLauncher.initialize,
            (WBNB, EXISTING_TOKEN_IMPL, EXISTING_LOCKER, address(0), V4_POSITION_MANAGER, 0, V4_POOL_MANAGER, address(0), V4_PERMIT2, address(0), LAUNCH_FEE)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        launcherProxy = address(proxy);
        console2.log("SparkGoLauncher proxy :", launcherProxy);
        vm.sleep(TX_DELAY_MS);

        SparkGoLauncher launcher = SparkGoLauncher(payable(launcherProxy));
        SparkLocker(EXISTING_LOCKER).setLauncher(launcherProxy);
        vm.sleep(TX_DELAY_MS);

        // See SparkGoHookFactory.sol's header comment for why this indirection is required.
        SparkGoHookFactory hookFactory = new SparkGoHookFactory();
        vm.sleep(TX_DELAY_MS);
        bytes memory hookV4Code = abi.encodePacked(
            type(SparkGoHookV4).creationCode,
            abi.encode(V4_POOL_MANAGER, launcherProxy, deployer)
        );
        bytes32 hookV4InitCodeHash = keccak256(hookV4Code);
        bytes32 hookV4Salt = _mineHookSalt(hookV4InitCodeHash, 0xC4, address(hookFactory));
        hookV4 = hookFactory.deploy(hookV4Salt, V4_POOL_MANAGER, launcherProxy, deployer, deployer);
        require(uint160(hookV4) & 0x3FFF == 0xC4, "hookV4 permission bits mismatch");
        require(SparkGoHookV4(payable(hookV4)).owner() == deployer, "hookV4 owner fixup failed");
        console2.log("SparkGoHookV4         :", hookV4);
        vm.sleep(TX_DELAY_MS);

        launcher.addDex(V4_POSITION_MANAGER, 0, V4_POOL_MANAGER, address(0), V4_PERMIT2, hookV4);
        vm.sleep(TX_DELAY_MS);

        hookInfinity = address(new SparkGoHookInfinity(INF_CL_POOL_MANAGER, launcherProxy, deployer));
        require(
            SparkGoHookInfinity(payable(hookInfinity)).getHooksRegistrationBitmap()
                == SparkGoHookInfinity(payable(hookInfinity)).REQUIRED_BITMAP(),
            "hookInfinity bitmap mismatch"
        );
        console2.log("SparkGoHookInfinity   :", hookInfinity);
        vm.sleep(TX_DELAY_MS);

        launcher.addDex(INF_POSITION_MANAGER, 1, INF_VAULT, INF_CL_POOL_MANAGER, INF_PERMIT2, hookInfinity);
        vm.sleep(TX_DELAY_MS);

        burner = address(new SparkGoBurner());
        console2.log("SparkGoBurner         :", burner);
        vm.sleep(TX_DELAY_MS);
        launcher.setBurner(burner);
        vm.sleep(TX_DELAY_MS);

        launcher.addQuoteToken(USDT, 2000 ether);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(USDC, 2000 ether);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(USD1, 2000 ether);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(AAPL, 6629321488945606656);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(NVDA, 10066438494060800000);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(TSLA, 4788469365767232512);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(SPCX, 18348623853211009024);
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

    function _mineHookSalt(bytes32 initCodeHash, uint160 requiredFlags, address deployerAddr) private view returns (bytes32 salt) {
        for (uint256 nonce; ; ++nonce) {
            salt = bytes32(nonce);
            address predicted = vm.computeCreate2Address(salt, initCodeHash, deployerAddr);
            if (uint160(predicted) & 0x3FFF == requiredFlags) return salt;
        }
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
