// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// Second resume of the DeploySparkCFEthereum sequence: the proxy deploy in
// DeploySparkCFEthereumResume failed gas estimation on 2026-08-18 with
// ERC1967InvalidImplementation because the RPC's view of chain state was one
// block behind the just-mined SparkCFLauncher impl deploy (confirmed present
// on-chain via cast codesize; not a contract bug). SparkCFToken impl,
// SparkLocker, and SparkCFLauncher impl are all already deployed and reused
// here as-is. Continues from the proxy deploy onward.

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkCFLauncher} from "spark-cf-contracts/SparkCFLauncher.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";

contract DeploySparkCFEthereumFinish is Script {
    address constant TOKEN_IMPL     = 0xB8e7F47466276d3208B8f2927DA090530BFAA470;
    address constant LOCKER         = 0xed9c99C8d06743D5aBFA22541c18Cb09eeEb9ecA;
    address constant LAUNCHER_IMPL  = 0x225648f06e030a68Bf980761bAD9f19d745b78Aa;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address constant AAPL = 0x14c3abF95Cb9C93a8b82C1CdCB76D72Cb87b2d4c;
    address constant NVDA = 0x2D1F7226Bd1F780AF6B9A49DCC0aE00E8Df4bDEE;
    address constant TSLA = 0xf6b1117ec07684D3958caD8BEb1b302bfD21103f;
    address constant SPCX = 0xc9eef266834730340A55B6CC24621B31BAF55581;

    address constant UNISWAP_V3_FACTORY          = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant UNISWAP_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant UNISWAP_V3_SWAP_ROUTER02    = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant UNISWAP_V2_ROUTER           = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address constant WETH_USDC_V3_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // fee=500
    address constant WETH_USDC_V2_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    uint8   constant USDC_DECIMALS_ETH = 6;
    uint32  constant TWAP_WINDOW = 1800;

    uint256 constant CAMPAIGN_FEE = 0.001111 ether;
    uint256 constant TX_DELAY_MS = 10000;

    function run() external returns (address launcherProxy) {
        vm.startBroadcast();

        bytes memory initData = abi.encodeCall(
            SparkCFLauncher.initialize,
            (WETH, TOKEN_IMPL, LOCKER, UNISWAP_V3_FACTORY, UNISWAP_V3_POSITION_MANAGER,
             UNISWAP_V2_ROUTER, address(0), CAMPAIGN_FEE)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(LAUNCHER_IMPL, initData);
        launcherProxy = address(proxy);
        console2.log("SparkCFLauncher proxy:", launcherProxy);
        vm.sleep(TX_DELAY_MS);

        SparkLocker(LOCKER).setLauncher(launcherProxy);
        vm.sleep(TX_DELAY_MS);

        SparkCFLauncher launcher = SparkCFLauncher(payable(launcherProxy));
        launcher.setV3TwapSource(WETH_USDC_V3_POOL, USDC, USDC_DECIMALS_ETH, TWAP_WINDOW);
        vm.sleep(TX_DELAY_MS);
        launcher.setV2TwapSource(WETH_USDC_V2_PAIR, USDC, USDC_DECIMALS_ETH, TWAP_WINDOW);
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

        vm.stopBroadcast();
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
