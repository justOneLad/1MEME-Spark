// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Deploys SparkCF on Ethereum: fresh SparkCFToken impl, a dedicated
// SparkLocker instance (used only by the 0%-tax V3 path), and the
// upgradeable SparkCFLauncher behind a UUPS proxy. Uniswap V3 (1% tier) for
// tax-free tokens, Uniswap V2 for taxed tokens (LP burned at seed time).
// V2 Router02 address confirmed on-chain (factory()/WETH() match canonical
// Uniswap V2 deployments) before use here. Also configures both TWAP
// goal-pricing sources — the deepest real WETH/USDC pools on each protocol,
// confirmed on-chain (getPool/getPair + liquidity/reserves) before use — and
// the dexQuoteAsset swap-at-finalize routes for every quote token already
// live on SparkLauncher/SparkGo on this chain (see Deployment.md), reusing
// the exact same route shapes (Uniswap only — PancakeSwap has no real
// liquidity for these pairs on Ethereum).

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SparkCFToken} from "spark-cf-contracts/SparkCFToken.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkCFLauncher} from "spark-cf-contracts/SparkCFLauncher.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";

contract DeploySparkCFEthereum is Script {
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

    // Deepest real WETH/USDC pools on each protocol, confirmed on-chain before use.
    address constant WETH_USDC_V3_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // fee=500
    address constant WETH_USDC_V2_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    uint8   constant USDC_DECIMALS_ETH = 6;
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
            (WETH, address(tokenImpl), address(locker), UNISWAP_V3_FACTORY, UNISWAP_V3_POSITION_MANAGER,
             UNISWAP_V2_ROUTER, address(0), CAMPAIGN_FEE)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        launcherProxy = address(proxy);
        console2.log("SparkCFLauncher proxy:", launcherProxy);
        vm.sleep(TX_DELAY_MS);

        locker.setLauncher(launcherProxy);
        vm.sleep(TX_DELAY_MS);

        SparkCFLauncher launcher = SparkCFLauncher(payable(launcherProxy));
        launcher.setV3TwapSource(WETH_USDC_V3_POOL, USDC, USDC_DECIMALS_ETH, TWAP_WINDOW);
        vm.sleep(TX_DELAY_MS);
        launcher.setV2TwapSource(WETH_USDC_V2_PAIR, USDC, USDC_DECIMALS_ETH, TWAP_WINDOW);
        vm.sleep(TX_DELAY_MS);

        // dexQuoteAsset swap-at-finalize routes — same set and shapes already live on
        // SparkLauncher/SparkGo on Ethereum.
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
