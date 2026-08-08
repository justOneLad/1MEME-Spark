// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// First Ethereum deploy: fresh SparkToken + per-launcher SparkLocker (nothing
// to reuse, unlike BSC). SparkGo is Uniswap v4 only (no Infinity on Ethereum).
// USDT/USDC are 6-decimal here (BSC's are 18) — marketCapRef scaled accordingly.

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SparkToken} from "spark-contracts/SparkToken.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {SparkGoHookV4} from "spark-go-contracts/hooks/SparkGoHookV4.sol";
import {SparkGoBurner} from "spark-go-contracts/SparkGoBurner.sol";
import {SparkGoHookFactory} from "./SparkGoHookFactory.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";

contract DeployEthereum is Script {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address constant AAPL = 0x14c3abF95Cb9C93a8b82C1CdCB76D72Cb87b2d4c;
    address constant NVDA = 0x2D1F7226Bd1F780AF6B9A49DCC0aE00E8Df4bDEE;
    address constant TSLA = 0xf6b1117ec07684D3958caD8BEb1b302bfD21103f;
    address constant SPCX = 0xc9eef266834730340A55B6CC24621B31BAF55581;

    address constant PANCAKE_V3_FACTORY          = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address constant PANCAKE_V3_POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address constant PANCAKE_V3_SMART_ROUTER     = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;

    address constant UNISWAP_V3_FACTORY          = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant UNISWAP_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant UNISWAP_V3_SWAP_ROUTER02    = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address constant UNISWAP_V4_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address constant UNISWAP_V4_POOL_MANAGER     = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant PERMIT2                     = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint256 constant LAUNCH_FEE = 0.001111 ether;
    uint256 constant TX_DELAY_MS = 10000;

    function run() external {
        vm.startBroadcast();
        address deployer = msg.sender;

        SparkToken tokenImpl = new SparkToken();
        console2.log("SparkToken impl :", address(tokenImpl));
        vm.sleep(TX_DELAY_MS);

        _deploySparkLauncher(deployer, address(tokenImpl));
        _deploySparkGo(deployer, address(tokenImpl));

        vm.stopBroadcast();
    }

    function _deploySparkLauncher(address deployer, address tokenImpl) private {
        SparkLocker locker = new SparkLocker(deployer);
        console2.log("SparkLauncher locker :", address(locker));
        vm.sleep(TX_DELAY_MS);

        SparkLauncher impl = new SparkLauncher();
        console2.log("SparkLauncher impl   :", address(impl));
        vm.sleep(TX_DELAY_MS);

        bytes memory initData = abi.encodeCall(
            SparkLauncher.initialize,
            (WETH, tokenImpl, address(locker), address(0), PANCAKE_V3_FACTORY, PANCAKE_V3_POSITION_MANAGER, PANCAKE_V3_SMART_ROUTER, true, LAUNCH_FEE)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console2.log("SparkLauncher proxy  :", address(proxy));
        vm.sleep(TX_DELAY_MS);

        SparkLauncher launcher = SparkLauncher(payable(address(proxy)));
        locker.setLauncher(address(proxy));
        vm.sleep(TX_DELAY_MS);
        launcher.addDex(UNISWAP_V3_FACTORY, UNISWAP_V3_POSITION_MANAGER, UNISWAP_V3_SWAP_ROUTER02, true);
        vm.sleep(TX_DELAY_MS);

        launcher.addQuoteToken(USDT, 2_000_000000, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(USDC, 2_000_000000, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(AAPL, 6496840312172192768, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(NVDA, 9729369681230909440, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(TSLA, 6285594853576460288, 0);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(SPCX, 19784418164216971264, 0);
        vm.sleep(TX_DELAY_MS);

        launcher.setRoutes(USDT, _singleHop(WETH, USDT, 3000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(USDC, _singleHop(WETH, USDC, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(AAPL, _multiHop(WETH, USDC, AAPL, 500, 3000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(NVDA, _multiHop(WETH, USDC, NVDA, 500, 10_000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(TSLA, _multiHop(WETH, USDC, TSLA, 500, 10_000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(SPCX, _multiHop(WETH, USDC, SPCX, 500, 10_000));
        vm.sleep(TX_DELAY_MS);
    }

    function _deploySparkGo(address deployer, address tokenImpl) private {
        SparkLocker locker = new SparkLocker(deployer);
        console2.log("SparkGo locker  :", address(locker));
        vm.sleep(TX_DELAY_MS);

        SparkGoLauncher impl = new SparkGoLauncher();
        console2.log("SparkGo impl    :", address(impl));
        vm.sleep(TX_DELAY_MS);

        bytes memory initData = abi.encodeCall(
            SparkGoLauncher.initialize,
            (WETH, tokenImpl, address(locker), address(0), UNISWAP_V4_POSITION_MANAGER, 0, UNISWAP_V4_POOL_MANAGER, address(0), PERMIT2, address(0), LAUNCH_FEE)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console2.log("SparkGo proxy   :", address(proxy));
        vm.sleep(TX_DELAY_MS);

        SparkGoLauncher launcher = SparkGoLauncher(payable(address(proxy)));
        locker.setLauncher(address(proxy));
        vm.sleep(TX_DELAY_MS);

        SparkGoHookFactory hookFactory = new SparkGoHookFactory();
        vm.sleep(TX_DELAY_MS);
        bytes memory hookCode = abi.encodePacked(
            type(SparkGoHookV4).creationCode,
            abi.encode(UNISWAP_V4_POOL_MANAGER, address(proxy), deployer)
        );
        bytes32 hookInitCodeHash = keccak256(hookCode);
        bytes32 hookSalt = _mineHookSalt(hookInitCodeHash, 0xC4, address(hookFactory));
        address hook = hookFactory.deploy(hookSalt, UNISWAP_V4_POOL_MANAGER, address(proxy), deployer, deployer);
        require(uint160(hook) & 0x3FFF == 0xC4, "hook permission bits mismatch");
        require(SparkGoHookV4(payable(hook)).owner() == deployer, "hook owner fixup failed");
        console2.log("SparkGoHookV4   :", hook);
        vm.sleep(TX_DELAY_MS);

        launcher.addDex(UNISWAP_V4_POSITION_MANAGER, 0, UNISWAP_V4_POOL_MANAGER, address(0), PERMIT2, hook);
        vm.sleep(TX_DELAY_MS);

        SparkGoBurner burner = new SparkGoBurner();
        console2.log("SparkGoBurner   :", address(burner));
        vm.sleep(TX_DELAY_MS);
        launcher.setBurner(address(burner));
        vm.sleep(TX_DELAY_MS);

        launcher.addQuoteToken(USDT, 2_000_000000);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(USDC, 2_000_000000);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(AAPL, 6496840312172192768);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(NVDA, 9729369681230909440);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(TSLA, 6285594853576460288);
        vm.sleep(TX_DELAY_MS);
        launcher.addQuoteToken(SPCX, 19784418164216971264);
        vm.sleep(TX_DELAY_MS);

        launcher.setRoutes(USDT, _singleHop(WETH, USDT, 3000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(USDC, _singleHop(WETH, USDC, 500));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(AAPL, _multiHop(WETH, USDC, AAPL, 500, 3000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(NVDA, _multiHop(WETH, USDC, NVDA, 500, 10_000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(TSLA, _multiHop(WETH, USDC, TSLA, 500, 10_000));
        vm.sleep(TX_DELAY_MS);
        launcher.setRoutes(SPCX, _multiHop(WETH, USDC, SPCX, 500, 10_000));
        vm.sleep(TX_DELAY_MS);
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
            shape: RouteShape.V3_STYLE, enabled: true, router: UNISWAP_V3_SWAP_ROUTER02, routerNoDeadline: true,
            path: path, fees: fees, routers: new address[](0), singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
    }

    function _multiHop(address tokenIn, address mid, address tokenOut, uint24 fee0, uint24 fee1) private pure returns (Route[] memory routes) {
        address[] memory path = new address[](3);
        path[0] = tokenIn; path[1] = mid; path[2] = tokenOut;
        uint24[] memory fees = new uint24[](2);
        fees[0] = fee0; fees[1] = fee1;
        routes = new Route[](1);
        routes[0] = Route({
            shape: RouteShape.V3_STYLE, enabled: true, router: UNISWAP_V3_SWAP_ROUTER02, routerNoDeadline: true,
            path: path, fees: fees, routers: new address[](0), singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
    }
}
