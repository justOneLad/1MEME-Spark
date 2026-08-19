// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Fork} from "./Fork.t.sol";
import {SparkCFToken} from "spark-cf-contracts/SparkCFToken.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkCFLauncher} from "spark-cf-contracts/SparkCFLauncher.sol";
import {Route, RouteShape} from "common-contracts/SparkRouting.sol";
import {TickMath} from "spark-cf-contracts/TickMath.sol";
import {FullMath} from "spark-cf-contracts/FullMath.sol";

interface IUniswapV3PoolSlot0Test {
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint32, bool);
}

interface IERC20Test {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

interface IUniswapV3PoolTest {
    function liquidity() external view returns (uint128);
}

interface IUniswapV2PairTest {
    function balanceOf(address) external view returns (uint256);
}

interface IUniswapV2FactoryTest {
    function getPair(address, address) external view returns (address);
}

interface IUniswapV2Router02Fork {
    function factory() external view returns (address);
    function WETH() external view returns (address);
}

interface IUniswapV2FactoryCreatePair {
    function createPair(address, address) external returns (address);
}

contract SparkCFLauncherForkTest is Fork {
    SparkCFToken    tokenImpl;
    SparkLocker     locker;
    SparkCFLauncher launcher;

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // Deepest real WBNB/USDT pools on BSC, same as DeploySparkCFBSC.s.sol.
    address constant WBNB_USDT_V3_POOL = 0x172fcD41E0913e95784454622d1c3724f546f849;
    address constant WBNB_USDT_V2_PAIR = 0x16b9a82891338f9bA80E2D6970FddA79D1eb0daE;
    uint8   constant USDT_DECIMALS = 18;
    uint32  constant TWAP_WINDOW = 1800;

    function setUp() public override {
        super.setUp();

        vm.startPrank(DEPLOYER);
        tokenImpl = new SparkCFToken();
        locker = new SparkLocker(DEPLOYER);

        SparkCFLauncher impl = new SparkCFLauncher();
        bytes memory initData = abi.encodeCall(
            SparkCFLauncher.initialize,
            (WBNB, address(tokenImpl), address(locker), PANCAKE_V3_FACTORY, PANCAKE_V3_POSITION_MANAGER,
             PANCAKE_V2_ROUTER, address(0), 0.001111 ether)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        launcher = SparkCFLauncher(payable(address(proxy)));
        locker.setLauncher(address(launcher));
        launcher.setV3TwapSource(WBNB_USDT_V3_POOL, USDT, USDT_DECIMALS, TWAP_WINDOW);
        vm.stopPrank();
    }

    function _create(address creator, address dexQuoteAsset, uint256 startTime, uint16 taxBps, address taxWallet)
        internal returns (uint256 campaignId, uint256 goal, uint256 deadline)
    {
        bytes32 vanitySalt = _mineVanitySalt(creator);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        campaignId = launcher.createCampaign{value: 0.001111 ether}(
            "Anti", "ANTI", "", dexQuoteAsset, startTime, taxBps, taxWallet, vanitySalt
        );
        (,,,,, goal,, deadline,,,,,,,,,) = launcher.campaigns(campaignId);
    }

    function test_v3Path_zeroTax_success_seedsTwoSidedLiquidityAndLockerFeeClaim() public {
        address creator = address(0xC1);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));
        assertGt(goal, 0);

        uint256 half = goal / 2;
        vm.deal(alice, half);
        vm.prank(alice);
        launcher.contribute{value: half}(id);

        uint256 rest = goal - half;
        vm.deal(bob, rest);
        vm.prank(bob);
        launcher.contribute{value: rest}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertNotEq(token, address(0));

        (,,,,,,,,,,,,,, bool finalized, bool succeeded, address storedToken) = launcher.campaigns(id);
        assertTrue(finalized);
        assertTrue(succeeded);
        assertEq(storedToken, token);

        uint256 contributorSupply = launcher.TOTAL_SUPPLY() * 8_000 / 10_000;
        vm.prank(alice);
        launcher.claim(id);
        assertEq(IERC20Test(token).balanceOf(alice), contributorSupply * half / goal);

        vm.prank(bob);
        launcher.claim(id);
        assertEq(IERC20Test(token).balanceOf(bob), contributorSupply * rest / goal);

        address pool = _getV3Pool(token);
        assertGt(IUniswapV3PoolTest(pool).liquidity(), 0);

        (, address feeWallet,,,,) = locker.positions(token);
        assertEq(feeWallet, creator);
    }

    // "Token launches at the same market cap the funding reaches" — using the LP-seeded (i.e.
    // circulating-at-launch) supply as the market-cap basis, the standard convention for a
    // freshly launched token, since the contributor-claimable portion isn't tradable yet. Uses an
    // overshoot scenario specifically to prove this tracks whatever totalRaised actually reaches,
    // not the original $8k goal target.
    function test_launchMarketCap_equalsActualTotalRaised_evenOnOvershoot() public {
        address creator = address(0xF6);
        address alice = address(0xA11CF5);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));

        uint256 overshootAmount = goal * 3; // well past the goal — still not capped
        vm.deal(alice, overshootAmount);
        vm.prank(alice);
        launcher.contribute{value: overshootAmount}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertNotEq(token, address(0));

        (,,,,,,,, uint256 totalRaised,,,,,,,,) = launcher.campaigns(id);
        assertEq(totalRaised, overshootAmount, "sanity: totalRaised must reflect the full overshoot, not the goal");

        address pool = _getV3Pool(token);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3PoolSlot0Test(pool).slot0();

        uint256 lpSupply = launcher.TOTAL_SUPPLY() * 2_000 / 10_000; // 20% default lpBps
        bool tokenIsToken0 = token < WBNB;
        uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
        // WBNB per 1 token, scaled 1e18, regardless of which side the token landed on.
        uint256 wbnbPerToken18 = tokenIsToken0
            ? FullMath.mulDiv(ratioX192, 1e18, 1 << 192)
            : FullMath.mulDiv(1 << 192, 1e18, ratioX192);

        uint256 launchMarketCapWei = FullMath.mulDiv(lpSupply, wbnbPerToken18, 1e18);

        uint256 diff = launchMarketCapWei > totalRaised ? launchMarketCapWei - totalRaised : totalRaised - launchMarketCapWei;
        assertLt(diff * 1000 / totalRaised, 1, "launch market cap (LP supply x pool price) must equal totalRaised almost exactly");
    }

    // Independently recomputes the expected native-wei goal from the pool's current spot tick
    // (not a copy of the contract's averaging loop) and cross-checks the contract's actual TWAP
    // output against it within a small tolerance for TWAP-vs-spot drift over the window — this is
    // the one calculation in the whole feature where a subtle unit/ordering error would otherwise
    // go undetected by a plain "does it revert" test.
    function test_twapGoal_matchesIndependentlyComputedSpotPrice() public {
        (, uint256 goal,) = _create(address(0xC0), address(0), 0, 0, address(0));
        assertGt(goal, 0);

        (, int24 tick,,,,,) = IUniswapV3PoolSlot0Test(WBNB_USDT_V3_POOL).slot0();
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
        // USDT < WBNB lexicographically (0x55d3... < 0xbb4C...), so token0 = USDT, token1 = WBNB:
        // sqrtRatioX96 encodes WBNB-per-USDT, the inverse of what we want — invert it, matching
        // the contract's own native_ < stable_ ? direct : inverted branch in _tickToUsdPerNative18.
        uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
        uint256 usdPerNative18 = FullMath.mulDiv(1 << 192, 1e18, ratioX192);
        uint256 expectedGoal = launcher.usdGoalTarget18() * 1e18 / usdPerNative18;

        uint256 diff = goal > expectedGoal ? goal - expectedGoal : expectedGoal - goal;
        assertLt(diff * 100 / expectedGoal, 2, "TWAP-derived goal must be within 2% of independently-computed spot price");
    }

    function test_v2Path_tax_success_burnsLPAndTaxesOnlyPairTransfers() public {
        address creator = address(0xC2);
        address taxWallet = address(0xFEE);
        address alice = address(0xA11CE2);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 300, taxWallet);

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertNotEq(token, address(0));

        address factory = IUniswapV2Router02Fork(PANCAKE_V2_ROUTER).factory();
        address weth = IUniswapV2Router02Fork(PANCAKE_V2_ROUTER).WETH();
        address pair = IUniswapV2FactoryTest(factory).getPair(token, weth);
        assertGt(IUniswapV2PairTest(pair).balanceOf(DEAD), 0);
        assertEq(IUniswapV2PairTest(pair).balanceOf(address(launcher)), 0);

        vm.prank(alice);
        launcher.claim(id);
        uint256 aliceBal = IERC20Test(token).balanceOf(alice);
        assertGt(aliceBal, 0);

        address bob = address(0xB0B2);
        vm.prank(alice);
        IERC20Test(token).transfer(bob, aliceBal);
        assertEq(IERC20Test(token).balanceOf(bob), aliceBal, "wallet-to-wallet transfer must be tax-free");
        assertEq(IERC20Test(token).balanceOf(taxWallet), 0, "no tax fired on wallet-to-wallet transfer");
    }

    function test_failedCampaign_refundsClaimable_noTokenDeployed() public {
        address creator = address(0xC3);
        address alice = address(0xA11CE3);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));

        uint256 partialAmt = goal / 3;
        vm.deal(alice, partialAmt);
        vm.prank(alice);
        launcher.contribute{value: partialAmt}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertEq(token, address(0));

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        launcher.claimRefund(id);
        assertEq(alice.balance, balBefore + partialAmt);

        vm.prank(alice);
        vm.expectRevert();
        launcher.claimRefund(id);

        vm.prank(alice);
        vm.expectRevert();
        launcher.claim(id);
    }

    function test_overshootDilution_largerRaiseYieldsSmallerClaimPerContributor() public {
        address creator1 = address(0xD1);
        address creator2 = address(0xD2);
        address alice = address(0xA11CE4);
        address carol = address(0xCA401);

        (uint256 id1, uint256 goal1,) = _create(creator1, address(0), 0, 0, address(0));
        (uint256 id2, uint256 goal2,) = _create(creator2, address(0), 0, 0, address(0));

        uint256 aliceAmt = goal1 / 2;
        vm.deal(alice, aliceAmt);
        vm.prank(alice);
        launcher.contribute{value: aliceAmt}(id1);

        vm.deal(carol, goal1 - aliceAmt);
        vm.prank(carol);
        launcher.contribute{value: goal1 - aliceAmt}(id1);

        vm.deal(alice, aliceAmt);
        vm.prank(alice);
        launcher.contribute{value: aliceAmt}(id2);

        uint256 overshoot = goal2 * 3;
        vm.deal(carol, overshoot);
        vm.prank(carol);
        launcher.contribute{value: overshoot}(id2);

        vm.warp(block.timestamp + 2 hours + 1);
        address token1 = launcher.finalize(id1);
        address token2 = launcher.finalize(id2);

        vm.prank(alice);
        launcher.claim(id1);
        uint256 aliceShareNoOvershoot = IERC20Test(token1).balanceOf(alice);

        vm.prank(alice);
        launcher.claim(id2);
        uint256 aliceShareWithOvershoot = IERC20Test(token2).balanceOf(alice);

        assertGt(aliceShareNoOvershoot, aliceShareWithOvershoot, "overshoot must dilute the same absolute contribution");
    }

    function test_vanityMismatch_finalizeDegradesToRefundableFailure() public {
        address creator = address(0xC4);
        address alice = address(0xA11CE6);
        bytes32 wrongSalt = bytes32(uint256(0xDEAD));

        vm.deal(creator, 1 ether);
        vm.prank(creator);
        uint256 id = launcher.createCampaign{value: 0.001111 ether}(
            "Anti", "ANTI", "", address(0), 0, 0, address(0), wrongSalt
        );
        (,,,,, uint256 goal,,,,,,,,,,,) = launcher.campaigns(id);

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertEq(token, address(0), "must degrade to failure, not revert");

        (,,,,,,,,,,,,,, bool finalized, bool succeeded,) = launcher.campaigns(id);
        assertTrue(finalized);
        assertFalse(succeeded);

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        launcher.claimRefund(id);
        assertEq(alice.balance, balBefore + goal);
    }

    function test_v2Path_revertsIfPairAlreadyExists() public {
        address creator = address(0xC5);
        address alice = address(0xA11CE7);
        bytes32 vanitySalt = _mineVanitySalt(creator);

        bytes32 salt = keccak256(abi.encode(creator, vanitySalt));
        address predictedToken = _predictClone(address(tokenImpl), salt, address(launcher));

        address factory = IUniswapV2Router02Fork(PANCAKE_V2_ROUTER).factory();
        vm.prank(DEPLOYER);
        IUniswapV2FactoryCreatePair(factory).createPair(predictedToken, WBNB);

        vm.deal(creator, 1 ether);
        vm.prank(creator);
        uint256 id = launcher.createCampaign{value: 0.001111 ether}(
            "Anti", "ANTI", "", address(0), 0, 200, address(0xFEE2), vanitySalt
        );
        (,,,,, uint256 goal,,,,,,,,,,,) = launcher.campaigns(id);

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertEq(token, address(0), "pair-already-exists must degrade to refundable failure");
    }

    function test_prelaunch_blocksContributeUntilStartTime() public {
        address creator = address(0xC6);
        uint256 futureStart = block.timestamp + 1 hours;
        (uint256 id,,) = _create(creator, address(0), futureStart, 0, address(0));

        vm.deal(address(this), 1 ether);
        vm.expectRevert();
        launcher.contribute{value: 1 ether}(id);

        vm.warp(futureStart);
        launcher.contribute{value: 1 ether}(id); // must not revert once live
    }

    function test_contribute_revertsAfterDeadline() public {
        (uint256 id,,) = _create(address(0xC7), address(0), 0, 0, address(0));
        vm.warp(block.timestamp + 2 hours + 1);
        vm.deal(address(this), 1 ether);
        vm.expectRevert();
        launcher.contribute{value: 1 ether}(id);
    }

    function test_finalize_revertsBeforeDeadline() public {
        (uint256 id,,) = _create(address(0xC8), address(0), 0, 0, address(0));
        vm.expectRevert();
        launcher.finalize(id);
    }

    function test_finalize_revertsOnDoubleFinalize() public {
        (uint256 id,,) = _create(address(0xC9), address(0), 0, 0, address(0));
        vm.warp(block.timestamp + 2 hours + 1);
        launcher.finalize(id);
        vm.expectRevert();
        launcher.finalize(id);
    }

    function test_createCampaign_revertsOnTaxBpsAboveMax() public {
        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));
        vm.expectRevert();
        launcher.createCampaign{value: 0.001111 ether}(
            "Anti", "ANTI", "", address(0), 0, 501, address(0xFEE3), salt
        );
    }

    function test_createCampaign_revertsOnMissingTaxWalletWhenTaxed() public {
        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));
        vm.expectRevert();
        launcher.createCampaign{value: 0.001111 ether}(
            "Anti", "ANTI", "", address(0), 0, 100, address(0), salt
        );
    }

    function test_createCampaign_revertsOnWrongCampaignFee() public {
        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));
        vm.expectRevert();
        launcher.createCampaign{value: 0.0005 ether}(
            "Anti", "ANTI", "", address(0), 0, 0, address(0), salt
        );
    }

    function test_createCampaign_revertsWithNoTwapSourceConfigured() public {
        vm.startPrank(DEPLOYER);
        SparkCFLauncher freshImpl = new SparkCFLauncher();
        bytes memory initData = abi.encodeCall(
            SparkCFLauncher.initialize,
            (WBNB, address(tokenImpl), address(locker), PANCAKE_V3_FACTORY, PANCAKE_V3_POSITION_MANAGER,
             PANCAKE_V2_ROUTER, address(0), 0.001111 ether)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(freshImpl), initData);
        SparkCFLauncher freshLauncher = SparkCFLauncher(payable(address(proxy)));
        vm.stopPrank();

        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySaltFor(address(this), address(freshLauncher));
        vm.expectRevert();
        freshLauncher.createCampaign{value: 0.001111 ether}(
            "Anti", "ANTI", "", address(0), 0, 0, address(0), salt
        );
    }

    function test_v2TwapWarmup_bootstrapsViaSpotPrice_thenBecomesRealAverage() public {
        vm.startPrank(DEPLOYER);
        SparkCFLauncher freshImpl = new SparkCFLauncher();
        bytes memory initData = abi.encodeCall(
            SparkCFLauncher.initialize,
            (WBNB, address(tokenImpl), address(locker), PANCAKE_V3_FACTORY, PANCAKE_V3_POSITION_MANAGER,
             PANCAKE_V2_ROUTER, address(0), 0.001111 ether)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(freshImpl), initData);
        SparkCFLauncher freshLauncher = SparkCFLauncher(payable(address(proxy)));
        freshLauncher.setV2TwapSource(WBNB_USDT_V2_PAIR, USDT, USDT_DECIMALS, TWAP_WINDOW);
        vm.stopPrank();

        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySaltFor(address(this), address(freshLauncher));

        // V2-only, not yet warmed: bootstraps via spot price, must not revert.
        uint256 id = freshLauncher.createCampaign{value: 0.001111 ether}(
            "Anti", "ANTI", "", address(0), 0, 0, address(0), salt
        );
        (,,,,, uint256 goalBootstrap,,,,,,,,,,,) = freshLauncher.campaigns(id);
        assertGt(goalBootstrap, 0);

        // After the window elapses, a second call uses the now-warmed real average.
        vm.warp(block.timestamp + TWAP_WINDOW + 1);
        bytes32 salt2 = _mineVanitySaltFor(address(0xBEEF9), address(freshLauncher));
        vm.deal(address(0xBEEF9), 1 ether);
        vm.prank(address(0xBEEF9));
        uint256 id2 = freshLauncher.createCampaign{value: 0.001111 ether}(
            "Anti2", "ANTI2", "", address(0), 0, 0, address(0), salt2
        );
        (,,,,, uint256 goalWarmed,,,,,,,,,,,) = freshLauncher.campaigns(id2);
        assertGt(goalWarmed, 0);
    }

    function test_dexQuoteAssetSwap_seedsLiquidityInSwappedCurrency() public {
        address creator = address(0xCA);
        address alice = address(0xA11CE9);

        vm.prank(DEPLOYER);
        launcher.setRoutes(USDT, _singleHop(WBNB, USDT, 100));

        (uint256 id, uint256 goal,) = _create(creator, USDT, 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertNotEq(token, address(0), "swap-then-seed must succeed with a configured route");

        address pool = _getV3PoolFor(token, USDT);
        assertNotEq(pool, address(0));
        assertGt(IUniswapV3PoolTest(pool).liquidity(), 0);
    }

    // ── claim() / claimRefund() edge cases ──────────────────────────────────

    function test_claimRefund_revertsOnSuccessfulCampaign() public {
        address creator = address(0xE1);
        address alice = address(0xA11CEA);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertNotEq(token, address(0));

        vm.prank(alice);
        vm.expectRevert(SparkCFLauncher.CampaignSucceeded_.selector);
        launcher.claimRefund(id);
    }

    function test_claim_revertsWithNothingToClaim_zeroContribution() public {
        address creator = address(0xE2);
        address alice = address(0xA11CEB);
        address bob = address(0xB0B3);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        launcher.finalize(id);

        vm.prank(bob); // bob never contributed
        vm.expectRevert(SparkCFLauncher.NothingToClaim.selector);
        launcher.claim(id);
    }

    function test_claimRefund_revertsWithNothingToClaim_zeroContribution() public {
        address creator = address(0xE3);
        address alice = address(0xA11CEC);
        address bob = address(0xB0B4);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));

        vm.deal(alice, goal / 3);
        vm.prank(alice);
        launcher.contribute{value: goal / 3}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        launcher.finalize(id); // under goal, fails

        vm.prank(bob);
        vm.expectRevert(SparkCFLauncher.NothingToClaim.selector);
        launcher.claimRefund(id);
    }

    function test_claim_revertsBeforeFinalized() public {
        (uint256 id,,) = _create(address(0xE4), address(0), 0, 0, address(0));
        vm.expectRevert(SparkCFLauncher.NotFinalized.selector);
        launcher.claim(id);
    }

    function test_claimRefund_revertsBeforeFinalized() public {
        (uint256 id,,) = _create(address(0xE5), address(0), 0, 0, address(0));
        vm.expectRevert(SparkCFLauncher.NotFinalized.selector);
        launcher.claimRefund(id);
    }

    function test_claim_revertsOnCampaignNotFound() public {
        vm.expectRevert(SparkCFLauncher.CampaignNotFound.selector);
        launcher.claim(999);
    }

    function test_claimRefund_revertsOnCampaignNotFound() public {
        vm.expectRevert(SparkCFLauncher.CampaignNotFound.selector);
        launcher.claimRefund(999);
    }

    function test_claim_doubleClaimReverts() public {
        address creator = address(0xE6);
        address alice = address(0xA11CED);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        launcher.finalize(id);

        vm.prank(alice);
        launcher.claim(id);

        vm.prank(alice);
        vm.expectRevert(SparkCFLauncher.NothingToClaim.selector);
        launcher.claim(id);
    }

    // ── finalize() / contribute() / createCampaign() edge cases ────────────

    function test_finalize_revertsOnCampaignNotFound() public {
        vm.expectRevert(SparkCFLauncher.CampaignNotFound.selector);
        launcher.finalize(999);
    }

    function test_contribute_revertsOnCampaignNotFound() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(SparkCFLauncher.CampaignNotFound.selector);
        launcher.contribute{value: 1 ether}(999);
    }

    function test_contribute_revertsOnZeroAmount() public {
        (uint256 id,,) = _create(address(0xE7), address(0), 0, 0, address(0));
        vm.expectRevert(SparkCFLauncher.ZeroAmount.selector);
        launcher.contribute{value: 0}(id);
    }

    function test_finalize_atExactGoal_succeeds() public {
        address creator = address(0xE8);
        address alice = address(0xA11CEE);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));

        // Contribute exactly the goal, no more, no less.
        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        (,,,,,,,, uint256 totalRaisedBefore,,,,,,,,) = launcher.campaigns(id);
        assertEq(totalRaisedBefore, goal, "sanity: totalRaised must equal goal exactly");

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertNotEq(token, address(0), "totalRaised == goal must count as success (>=, not >)");
    }

    function test_finalize_zeroContributions_failsGracefully() public {
        (uint256 id,,) = _create(address(0xE9), address(0), 0, 0, address(0));
        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);
        assertEq(token, address(0));
        (,,,,,,,,,,,,,, bool finalized, bool succeeded,) = launcher.campaigns(id);
        assertTrue(finalized);
        assertFalse(succeeded);
    }

    function test_finalize_exactlyAtDeadlineBoundary_succeeds() public {
        address creator = address(0xEA);
        address alice = address(0xA11CEF);
        (uint256 id, uint256 goal, uint256 deadline) = _create(creator, address(0), 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(deadline); // exactly at the boundary — `>=` means finalize must already work
        address token = launcher.finalize(id);
        assertNotEq(token, address(0));
    }

    function test_contribute_revertsExactlyAtDeadlineBoundary() public {
        (uint256 id,, uint256 deadline) = _create(address(0xEB), address(0), 0, 0, address(0));
        vm.warp(deadline); // exactly at the boundary — `>=` means contribute must already be closed
        vm.deal(address(this), 1 ether);
        vm.expectRevert(SparkCFLauncher.DeadlinePassed.selector);
        launcher.contribute{value: 1 ether}(id);
    }

    function test_finalize_callableByAnyone_notJustCreator() public {
        address creator = address(0xEC);
        address alice = address(0xA11CF0);
        address rando = address(0xBEEFA);
        (uint256 id, uint256 goal,) = _create(creator, address(0), 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        vm.prank(rando); // not the creator
        address token = launcher.finalize(id);
        assertNotEq(token, address(0));
    }

    function test_createCampaign_succeedsAtExactlyMaxTaxBps() public {
        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));
        launcher.createCampaign{value: 0.001111 ether}(
            "Anti", "ANTI", "", address(0), 0, 500, address(0xFEEB), salt
        ); // 500 == MAX_TAX_BPS, must not revert
    }

    function test_deploySuccessToken_revertsIfCalledDirectly() public {
        vm.expectRevert(); // Unauthorized is inherited from SparkRouting
        launcher._deploySuccessToken(0);
    }

    // ── Owner-setter access control / validation ────────────────────────────

    function test_setSupplySplit_revertsOnInvalidBps() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(SparkCFLauncher.InvalidBps.selector);
        launcher.setSupplySplit(7_000, 2_000); // doesn't sum to 10_000
    }

    function test_defaultUsdGoalTarget_is3000() public view {
        assertEq(launcher.usdGoalTarget18(), 3_000e18);
    }

    function test_setUsdGoalTarget_revertsOnZero() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(SparkCFLauncher.ZeroAmount.selector);
        launcher.setUsdGoalTarget(0);
    }

    function test_setUsdGoalTarget_ownerCanSetToAnyNonzeroValue() public {
        uint256 newTarget = 500e18; // owner-settable, no minimum floor
        vm.prank(DEPLOYER);
        launcher.setUsdGoalTarget(newTarget);
        assertEq(launcher.usdGoalTarget18(), newTarget);
    }

    function test_setUsdGoalTarget_onlyOwner() public {
        vm.expectRevert();
        launcher.setUsdGoalTarget(5_000e18);
    }

    function test_setSupplySplit_onlyOwner() public {
        vm.expectRevert();
        launcher.setSupplySplit(8_000, 2_000);
    }

    function test_setTokenImpl_onlyOwner() public {
        vm.expectRevert();
        launcher.setTokenImpl(address(0x1234));
    }

    function test_setV3TwapSource_onlyOwner() public {
        vm.expectRevert();
        launcher.setV3TwapSource(WBNB_USDT_V3_POOL, USDT, USDT_DECIMALS, TWAP_WINDOW);
    }

    function test_setV2TwapSource_resetsAccumulatorOnPairChange() public {
        vm.startPrank(DEPLOYER);
        launcher.setV2TwapSource(WBNB_USDT_V2_PAIR, USDT, USDT_DECIMALS, TWAP_WINDOW);
        vm.stopPrank();

        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));
        launcher.createCampaign{value: 0.001111 ether}("Anti", "ANTI", "", address(0), 0, 0, address(0), salt);
        assertGt(launcher.v2BlockTimestampLast(), 0, "sanity: first snapshot must have been taken");

        vm.prank(DEPLOYER);
        launcher.setV2TwapSource(WBNB_USDT_V2_PAIR, USDT, USDT_DECIMALS, TWAP_WINDOW);
        assertEq(launcher.v2BlockTimestampLast(), 0, "changing the V2 source must reset the accumulator");
        assertEq(launcher.v2PriceAverage(), 0);
    }

    // ── SparkCFToken direct edge cases ──────────────────────────────────────

    function test_token_setPair_revertsOnSecondCall() public {
        SparkCFToken t = SparkCFToken(Clones.clone(address(tokenImpl)));
        t.initSparkCF("Anti", "ANTI", "", 0, address(0));
        t.setPair(address(0xFEEC));
        vm.expectRevert(SparkCFToken.PairAlreadySet.selector);
        t.setPair(address(0xFEED));
    }

    function test_token_setPair_revertsOnZeroAddress() public {
        SparkCFToken t = SparkCFToken(Clones.clone(address(tokenImpl)));
        t.initSparkCF("Anti", "ANTI", "", 0, address(0));
        vm.expectRevert(SparkCFToken.PairZeroAddress.selector);
        t.setPair(address(0));
    }

    function test_token_setPair_onlyOwner() public {
        SparkCFToken t = SparkCFToken(Clones.clone(address(tokenImpl)));
        t.initSparkCF("Anti", "ANTI", "", 0, address(0));
        vm.prank(address(0xBEEFB));
        vm.expectRevert(SparkCFToken.NotOwner.selector);
        t.setPair(address(0xFEEC));
    }

    function test_token_initSparkCF_revertsOnDoubleInit() public {
        SparkCFToken t = SparkCFToken(Clones.clone(address(tokenImpl)));
        t.initSparkCF("Anti", "ANTI", "", 0, address(0));
        vm.expectRevert(SparkCFToken.AlreadyInitialized.selector);
        t.initSparkCF("Anti2", "ANTI2", "", 0, address(0));
    }

    function test_token_initSparkCF_revertsOnTaxTooHigh() public {
        SparkCFToken t = SparkCFToken(Clones.clone(address(tokenImpl)));
        vm.expectRevert(SparkCFToken.TaxTooHigh.selector);
        t.initSparkCF("Anti", "ANTI", "", 501, address(0xFEEC));
    }

    function test_token_initSparkCF_revertsOnMissingTaxWallet() public {
        SparkCFToken t = SparkCFToken(Clones.clone(address(tokenImpl)));
        vm.expectRevert(SparkCFToken.ZeroAddress.selector);
        t.initSparkCF("Anti", "ANTI", "", 100, address(0));
    }

    // ── Preview views ────────────────────────────────────────────────────────

    function test_previewGoalNativeWei_matchesActualCreatedGoal() public {
        uint256 previewed = launcher.previewGoalNativeWei();
        assertGt(previewed, 0);

        (, uint256 goal,) = _create(address(0xF1), address(0), 0, 0, address(0));
        assertEq(goal, previewed, "preview must match the goal actually recorded at creation (same block)");
    }

    function test_previewGoalNativeWei_revertsWithNoTwapSourceConfigured() public {
        vm.startPrank(DEPLOYER);
        SparkCFLauncher freshImpl = new SparkCFLauncher();
        bytes memory initData = abi.encodeCall(
            SparkCFLauncher.initialize,
            (WBNB, address(tokenImpl), address(locker), PANCAKE_V3_FACTORY, PANCAKE_V3_POSITION_MANAGER,
             PANCAKE_V2_ROUTER, address(0), 0.001111 ether)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(freshImpl), initData);
        SparkCFLauncher freshLauncher = SparkCFLauncher(payable(address(proxy)));
        vm.stopPrank();

        vm.expectRevert(SparkCFLauncher.NoTwapSourceConfigured.selector);
        freshLauncher.previewGoalNativeWei();
    }

    function test_previewClaimable_zeroBeforeFinalized() public {
        address alice = address(0xA11CF1);
        (uint256 id, uint256 goal,) = _create(address(0xF2), address(0), 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        assertEq(launcher.previewClaimable(id, alice), 0, "must be 0 before finalize, even with a real contribution");
    }

    function test_previewClaimable_zeroForNonContributor() public {
        address alice = address(0xA11CF2);
        address bob = address(0xB0B5);
        (uint256 id, uint256 goal,) = _create(address(0xF3), address(0), 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        launcher.finalize(id);

        assertEq(launcher.previewClaimable(id, bob), 0);
    }

    function test_previewClaimable_matchesActualClaimedAmount() public {
        address alice = address(0xA11CF3);
        (uint256 id, uint256 goal,) = _create(address(0xF4), address(0), 0, 0, address(0));

        vm.deal(alice, goal);
        vm.prank(alice);
        launcher.contribute{value: goal}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        address token = launcher.finalize(id);

        uint256 previewed = launcher.previewClaimable(id, alice);
        assertGt(previewed, 0);

        vm.prank(alice);
        launcher.claim(id);
        assertEq(IERC20Test(token).balanceOf(alice), previewed, "actual claim must match the preview exactly");

        assertEq(launcher.previewClaimable(id, alice), 0, "must be 0 again after claiming");
    }

    function test_previewClaimable_zeroForFailedCampaign() public {
        address alice = address(0xA11CF4);
        (uint256 id, uint256 goal,) = _create(address(0xF5), address(0), 0, 0, address(0));

        vm.deal(alice, goal / 3);
        vm.prank(alice);
        launcher.contribute{value: goal / 3}(id);

        vm.warp(block.timestamp + 2 hours + 1);
        launcher.finalize(id); // under goal, fails

        assertEq(launcher.previewClaimable(id, alice), 0, "must be 0 for a failed campaign - refund path applies instead");
    }

    function test_previewClaimable_revertsOnCampaignNotFound() public {
        vm.expectRevert(SparkCFLauncher.CampaignNotFound.selector);
        launcher.previewClaimable(999, address(this));
    }

    function _getV3Pool(address token) internal view returns (address) {
        return _getV3PoolFor(token, WBNB);
    }

    function _getV3PoolFor(address token, address quote) internal view returns (address) {
        (bool ok, bytes memory data) = PANCAKE_V3_FACTORY.staticcall(
            abi.encodeWithSignature("getPool(address,address,uint24)", token, quote, uint24(10_000))
        );
        require(ok, "getPool failed");
        return abi.decode(data, (address));
    }

    function _predictClone(address impl, bytes32 salt, address deployer) internal pure returns (address) {
        bytes32 initCodeHash = keccak256(abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", impl, hex"5af43d82803e903d91602b57fd5bf3"
        ));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }

    function _singleHop(address tokenIn, address tokenOut, uint24 fee) internal view returns (Route[] memory routes) {
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

    function _mineVanitySalt(address creator) internal view returns (bytes32) {
        return _mineVanitySaltFor(creator, address(launcher));
    }

    // Pure-assembly CREATE2 search, entirely in fixed scratch memory (never bumps the free memory
    // pointer) — an unlucky (creator, launcher) pair can need hundreds of thousands of iterations
    // to find a matching vanity suffix, and EVM memory never shrinks within a call, so any
    // per-iteration abi.encode/abi.encodePacked (even indirectly, e.g. via a cheatcode call's own
    // calldata encoding) eventually blows up with MemoryOOG. Reusing the same scratch region every
    // iteration is the standard fix (same trick OpenZeppelin's Create2.computeAddress uses).
    function _mineVanitySaltFor(address creator, address launcherAddr) internal view returns (bytes32 vanitySalt) {
        bytes32 initCodeHash = keccak256(abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", address(tokenImpl), hex"5af43d82803e903d91602b57fd5bf3"
        ));
        for (uint256 nonce; ; ++nonce) {
            vanitySalt = bytes32(nonce);
            bytes32 actualSalt;
            assembly ("memory-safe") {
                let p := mload(0x40)
                mstore(p, creator)
                mstore(add(p, 0x20), vanitySalt)
                actualSalt := keccak256(p, 0x40)
            }
            address predicted;
            assembly ("memory-safe") {
                let ptr := mload(0x40)
                mstore(add(ptr, 0x40), initCodeHash)
                mstore(add(ptr, 0x20), actualSalt)
                mstore(ptr, launcherAddr)
                let start := add(ptr, 0x0b)
                mstore8(start, 0xff)
                predicted := and(keccak256(start, 85), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            if (uint16(uint160(predicted)) == 0x1111) return vanitySalt;
        }
    }
}
