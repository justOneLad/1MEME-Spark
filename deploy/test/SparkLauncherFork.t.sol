// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Fork} from "./Fork.t.sol";
import {SparkToken} from "spark-contracts/SparkToken.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {Route, RouteShape, IV3SwapRouterNoDeadline, IWETH} from "common-contracts/SparkRouting.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

contract SparkLauncherForkTest is Fork {
    SparkToken   tokenImpl;
    SparkLocker  locker;
    SparkLauncher launcher;

    function setUp() public override {
        super.setUp();

        vm.startPrank(DEPLOYER);
        tokenImpl = new SparkToken();
        locker = new SparkLocker(DEPLOYER);

        SparkLauncher impl = new SparkLauncher();
        bytes memory initData = abi.encodeCall(
            SparkLauncher.initialize,
            (WBNB, address(tokenImpl), address(locker), address(0), PANCAKE_V3_FACTORY, PANCAKE_V3_POSITION_MANAGER, PANCAKE_V3_SMART_ROUTER, true, 0.001111 ether)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        launcher = SparkLauncher(payable(address(proxy)));

        locker.setLauncher(address(launcher));
        launcher.addDex(UNISWAP_V3_FACTORY, UNISWAP_V3_POSITION_MANAGER, UNISWAP_V3_SWAP_ROUTER02, true);
        launcher.addQuoteToken(USDT, 2000 ether, 0);
        launcher.addQuoteToken(NVDA, 10_066438494060800000, 0);
        vm.stopPrank();
    }

    function test_plainWbnbLaunchSucceeds() public {
        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));

        SparkLauncher.LaunchParams memory p = SparkLauncher.LaunchParams({
            name: "Test", symbol: "TST", metaURI: "",
            feeWallet: address(0), factory: PANCAKE_V3_FACTORY, quoteToken: WBNB,
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: false
        });
        (address token, address pool, uint256 tokenId) = launcher.launch{value: 0.001111 ether}(p);

        assertEq(uint16(uint160(token)), 0x1111, "vanity suffix enforced");
        assertTrue(pool != address(0));
        assertTrue(tokenId != 0);
    }

    function test_nvdaLaunchWithInstantBuy_succeedsViaUsdtMultihopRoute() public {
        vm.startPrank(DEPLOYER);
        address[] memory path = new address[](3);
        path[0] = WBNB; path[1] = USDT; path[2] = NVDA;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500; // deepest real USDT/WBNB pool tier
        fees[1] = NVDA_USDT_FEE;

        Route[] memory routes = new Route[](1);
        routes[0] = Route({
            shape: RouteShape.V3_STYLE, enabled: true, router: PANCAKE_V3_SMART_ROUTER, routerNoDeadline: true,
            path: path, fees: fees, routers: new address[](0), singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
        launcher.setRoutes(NVDA, routes);
        vm.stopPrank();

        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));

        SparkLauncher.LaunchParams memory p = SparkLauncher.LaunchParams({
            name: "SparkNVDA", symbol: "SNVDA", metaURI: "",
            feeWallet: address(0), factory: PANCAKE_V3_FACTORY, quoteToken: NVDA,
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: true
        });
        (address token,,) = launcher.launch{value: 0.001111 ether + 0.01 ether}(p);

        assertGt(IERC20(token).balanceOf(address(this)), 0, "instant buy must have delivered tokens to the creator");
    }

    function test_spcxLaunchWithInstantBuy_succeedsViaCrossDexChainedRoute() public {
        vm.startPrank(DEPLOYER);
        launcher.addQuoteToken(SPCX, 18_348623853211009024, 0);

        address[] memory path = new address[](3);
        path[0] = WBNB; path[1] = USDT; path[2] = SPCX;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500; // WBNB/USDT, deepest on PancakeSwap
        fees[1] = SPCX_USDT_FEE; // USDT/SPCX, only real liquidity is on Uniswap
        address[] memory hopRouters = new address[](2);
        hopRouters[0] = PANCAKE_V3_SMART_ROUTER;
        hopRouters[1] = UNISWAP_V3_SWAP_ROUTER02;

        Route[] memory routes = new Route[](1);
        routes[0] = Route({
            shape: RouteShape.V3_STYLE, enabled: true, router: address(0), routerNoDeadline: true,
            path: path, fees: fees, routers: hopRouters, singleton: address(0), poolLogic: address(0), hook: address(0),
            fee: 0, tickSpacing: 0, parameters: bytes32(0)
        });
        launcher.setRoutes(SPCX, routes);
        vm.stopPrank();

        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));

        SparkLauncher.LaunchParams memory p = SparkLauncher.LaunchParams({
            name: "SparkSPCX", symbol: "SSPCX", metaURI: "",
            feeWallet: address(0), factory: PANCAKE_V3_FACTORY, quoteToken: SPCX,
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: true
        });
        (address token,,) = launcher.launch{value: 0.001111 ether + 0.001 ether}(p);

        assertGt(IERC20(token).balanceOf(address(this)), 0, "instant buy must have crossed PancakeSwap then Uniswap to deliver tokens");
    }

    function test_allRoutesFailing_withRevertFalse_skipsAndRefunds() public {
        vm.prank(DEPLOYER);
        launcher.addQuoteToken(USDC, 2000 ether, 0); // enabled, but zero routes configured

        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));
        uint256 balBefore = address(this).balance;

        SparkLauncher.LaunchParams memory p = SparkLauncher.LaunchParams({
            name: "NoRoute", symbol: "NRT", metaURI: "",
            feeWallet: address(0), factory: PANCAKE_V3_FACTORY, quoteToken: USDC,
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: false
        });
        uint256 extra = 0.01 ether;
        (address token,,) = launcher.launch{value: 0.001111 ether + extra}(p);

        assertTrue(token != address(0), "launch itself must still succeed");
        assertEq(address(this).balance, balBefore - 0.001111 ether, "extra ETH must be refunded, only the launch fee kept");
    }

    function test_fullLifecycle_tradeFeesClaimAndCTO() public {
        address feeWallet = address(0xFEE);
        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));

        SparkLauncher.LaunchParams memory p = SparkLauncher.LaunchParams({
            name: "Life", symbol: "LIFE", metaURI: "",
            feeWallet: feeWallet, factory: PANCAKE_V3_FACTORY, quoteToken: WBNB,
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: true
        });
        (address token,,) = launcher.launch{value: 0.001111 ether + 0.05 ether}(p);

        address trader = address(0xBEEF);
        vm.deal(trader, 1 ether);
        vm.startPrank(trader);
        IWETH(WBNB).deposit{value: 0.02 ether}();
        IERC20(WBNB).approve(PANCAKE_V3_SMART_ROUTER, 0.02 ether);
        IV3SwapRouterNoDeadline(PANCAKE_V3_SMART_ROUTER).exactInputSingle(
            IV3SwapRouterNoDeadline.ExactInputSingleParams({
                tokenIn: WBNB, tokenOut: token, fee: 10_000, recipient: trader,
                amountIn: 0.02 ether, amountOutMinimum: 0, sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();

        uint256 traderTokens = IERC20(token).balanceOf(trader);
        assertGt(traderTokens, 0, "trader must have received tokens from the buy");

        vm.startPrank(trader);
        IERC20(token).approve(PANCAKE_V3_SMART_ROUTER, traderTokens / 2);
        IV3SwapRouterNoDeadline(PANCAKE_V3_SMART_ROUTER).exactInputSingle(
            IV3SwapRouterNoDeadline.ExactInputSingleParams({
                tokenIn: token, tokenOut: WBNB, fee: 10_000, recipient: trader,
                amountIn: traderTokens / 2, amountOutMinimum: 0, sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();

        (,, uint256 pendingAmount0, uint256 pendingAmount1) = locker.pendingCreatorFees(token);
        assertTrue(pendingAmount0 > 0 || pendingAmount1 > 0, "real LP fees must have accrued from the buy+sell");

        vm.prank(feeWallet);
        locker.claimFees(token);
        (, address posFeeWallet, address posToken0, address posToken1,,) = locker.positions(token);
        assertEq(posFeeWallet, feeWallet);
        assertTrue(IERC20(posToken0).balanceOf(feeWallet) > 0 || IERC20(posToken1).balanceOf(feeWallet) > 0, "fee wallet must have received claimed fees");

        address applicant = address(0xC7A);
        address newCreator = address(0xC7A0002);
        vm.deal(applicant, 1 ether);
        vm.prank(applicant);
        locker.applyForCTO{value: 0.1 ether}(token, newCreator);
        vm.prank(DEPLOYER);
        locker.approveCTO(token);
        (, address updatedFeeWallet,,,,) = locker.positions(token);
        assertEq(updatedFeeWallet, newCreator, "CTO must reassign the fee wallet");
    }

    receive() external payable {}

    function _mineVanitySalt(address creator) internal view returns (bytes32) {
        bytes32 initCodeHash = keccak256(abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", address(tokenImpl), hex"5af43d82803e903d91602b57fd5bf3"
        ));
        for (uint256 nonce; ; ++nonce) {
            bytes32 vanitySalt = bytes32(nonce);
            bytes32 actualSalt = keccak256(abi.encode(creator, vanitySalt));
            address predicted = vm.computeCreate2Address(actualSalt, initCodeHash, address(launcher));
            if (uint16(uint160(predicted)) == 0x1111) return vanitySalt;
        }
    }
}
