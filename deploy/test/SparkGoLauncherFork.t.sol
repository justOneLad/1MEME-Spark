// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Fork} from "./Fork.t.sol";
import {SparkToken} from "spark-contracts/SparkToken.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {SparkGoHookV4} from "spark-go-contracts/hooks/SparkGoHookV4.sol";
import {SparkGoBurner} from "spark-go-contracts/SparkGoBurner.sol";
import {V4PoolKey, V4SwapParams, IV4PoolManagerSwap} from "common-contracts/SparkRouting.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

/// @dev v4 pools have no plain router — implements the unlock callback directly.
contract V4Trader {
    address public immutable poolManager;
    uint160 constant MIN_SQRT_PRICE = 4295128739;
    uint160 constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    constructor(address poolManager_) { poolManager = poolManager_; }

    function buy(address hook_, address token_, uint256 amountIn) external payable returns (uint256 amountOut) {
        bytes memory result = IV4PoolManagerSwap(poolManager).unlock(abi.encode(true, hook_, token_, amountIn));
        amountOut = abi.decode(result, (uint256));
    }

    function sell(address hook_, address token_, uint256 amountIn) external returns (uint256 amountOut) {
        bytes memory result = IV4PoolManagerSwap(poolManager).unlock(abi.encode(false, hook_, token_, amountIn));
        amountOut = abi.decode(result, (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == poolManager, "unauthorized");
        (bool isBuy, address hook_, address token_, uint256 amountIn) = abi.decode(data, (bool, address, address, uint256));

        V4PoolKey memory key = V4PoolKey({currency0: address(0), currency1: token_, fee: 0, tickSpacing: 200, hooks: hook_});
        int256 delta = IV4PoolManagerSwap(poolManager).swap(
            key,
            V4SwapParams({
                zeroForOne: isBuy,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: isBuy ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        uint256 amountOut;
        if (isBuy) {
            amountOut = uint256(uint128(int128(delta))); // lower 128 bits = currency1 (token) delta
            IV4PoolManagerSwap(poolManager).settle{value: amountIn}();
            IV4PoolManagerSwap(poolManager).take(token_, address(this), amountOut);
        } else {
            amountOut = uint256(uint128(int128(delta >> 128))); // upper 128 bits = currency0 (native) delta
            IV4PoolManagerSwap(poolManager).sync(token_);
            IERC20(token_).transfer(poolManager, amountIn);
            IV4PoolManagerSwap(poolManager).settle();
            IV4PoolManagerSwap(poolManager).take(address(0), address(this), amountOut);
        }
        return abi.encode(amountOut);
    }

    receive() external payable {}
}

contract SparkGoLauncherForkTest is Fork {
    SparkToken     tokenImpl;
    SparkLocker    locker;
    SparkGoLauncher launcher;
    SparkGoHookV4   hook;

    function setUp() public override {
        super.setUp();

        vm.startPrank(DEPLOYER);
        tokenImpl = new SparkToken();
        locker = new SparkLocker(DEPLOYER);

        SparkGoLauncher impl = new SparkGoLauncher();
        bytes memory initData = abi.encodeCall(
            SparkGoLauncher.initialize,
            (WBNB, address(tokenImpl), address(locker), address(0), UNISWAP_V4_POSITION_MANAGER, 0, UNISWAP_V4_POOL_MANAGER, address(0), UNISWAP_V4_PERMIT2, address(0), 0.001111 ether)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        launcher = SparkGoLauncher(payable(address(proxy)));

        locker.setLauncher(address(launcher));
        vm.stopPrank();

        // Deployed outside any active prank — CREATE2's deployer must match msg.sender for `owner = msg.sender`.
        bytes32 hookSalt = _mineHookSalt(UNISWAP_V4_POOL_MANAGER, address(launcher), address(this));
        hook = new SparkGoHookV4{salt: hookSalt}(UNISWAP_V4_POOL_MANAGER, address(launcher), address(this));
        require(uint160(address(hook)) & 0x3FFF == 0xC4, "hook permission bits mismatch");

        vm.prank(DEPLOYER);
        launcher.addDex(UNISWAP_V4_POSITION_MANAGER, 0, UNISWAP_V4_POOL_MANAGER, address(0), UNISWAP_V4_PERMIT2, address(hook));
    }

    function test_nativeBnbQuotedLaunch_matchesOriginalBehavior() public {
        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));

        SparkGoLauncher.LaunchParams memory p = SparkGoLauncher.LaunchParams({
            name: "Test", symbol: "TST", metaURI: "",
            feeWallet: address(this), positionManager: UNISWAP_V4_POSITION_MANAGER, quoteToken: address(0),
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: true
        });
        (address token, bytes32 poolId, uint256 tokenId) = launcher.launch{value: 0.001111 ether + 0.01 ether}(p);

        assertEq(uint16(uint160(token)), 0x1111, "vanity suffix enforced");
        assertTrue(poolId != bytes32(0));
        assertTrue(tokenId != 0);
        assertGt(IERC20(token).balanceOf(address(this)), 0, "instant buy must have delivered tokens");
    }

    function test_erc20QuotedLaunch_tokenAsCurrency0() public {
        vm.prank(DEPLOYER);
        launcher.addQuoteToken(USDT, 2000 ether);

        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySaltBelow(address(this), USDT);

        SparkGoLauncher.LaunchParams memory p = SparkGoLauncher.LaunchParams({
            name: "Below", symbol: "BLW", metaURI: "",
            feeWallet: address(this), positionManager: UNISWAP_V4_POSITION_MANAGER, quoteToken: USDT,
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: false
        });
        (address token,,) = launcher.launch{value: 0.001111 ether}(p);
        assertLt(uint160(token), uint160(USDT), "token must sort below USDT for this branch to be exercised");
    }

    function test_erc20QuotedLaunch_tokenAsCurrency1() public {
        address lowQuote = address(0x1000);
        vm.prank(DEPLOYER);
        launcher.addQuoteToken(lowQuote, 1 ether);

        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this)); // token always ends 0x1111, so > 0x1000

        SparkGoLauncher.LaunchParams memory p = SparkGoLauncher.LaunchParams({
            name: "Above", symbol: "ABV", metaURI: "",
            feeWallet: address(this), positionManager: UNISWAP_V4_POSITION_MANAGER, quoteToken: lowQuote,
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: false
        });
        (address token,,) = launcher.launch{value: 0.001111 ether}(p);
        assertGt(uint160(token), uint160(lowQuote), "token must sort above the quote token for this branch to be exercised");
    }

    function test_fullLifecycle_tradeFeesClaimCTOAndBurn() public {
        address creator = address(0xFEE);
        vm.deal(address(this), 1 ether);
        bytes32 salt = _mineVanitySalt(address(this));

        SparkGoLauncher.LaunchParams memory p = SparkGoLauncher.LaunchParams({
            name: "Life", symbol: "LIFE", metaURI: "",
            feeWallet: creator, positionManager: UNISWAP_V4_POSITION_MANAGER, quoteToken: address(0),
            vanitySalt: salt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: true
        });
        (address token,,) = launcher.launch{value: 0.001111 ether + 0.02 ether}(p);

        V4PoolKey memory key = V4PoolKey({currency0: address(0), currency1: token, fee: 0, tickSpacing: 200, hooks: address(hook)});
        bytes32 poolId = keccak256(abi.encode(key));

        V4Trader trader = new V4Trader(UNISWAP_V4_POOL_MANAGER);
        trader.buy{value: 0.02 ether}(address(hook), token, 0.02 ether);
        uint256 traderTokens = IERC20(token).balanceOf(address(trader));
        assertGt(traderTokens, 0, "trader must have received tokens from the buy");

        uint256 startBlock = block.number;
        vm.roll(startBlock + 10); // SameBlockSwap guard: same sender can't swap twice in one block
        trader.sell(address(hook), token, traderTokens / 2);

        uint256 accrued = hook.accruedFees(poolId);
        assertGt(accrued, 0, "hook must have taken its 2% sell fee in native BNB");

        uint256 creatorBalBefore = creator.balance;
        uint256 platformBalBefore = hook.platformWallet().balance;
        hook.claimFees(poolId);
        assertGt(creator.balance, creatorBalBefore, "creator must have received their share");
        assertGt(hook.platformWallet().balance, platformBalBefore, "platform must have received its share");

        address applicant = address(0xC7A);
        address newCreator = address(0xC7A0002);
        vm.deal(applicant, 1 ether);
        vm.prank(applicant);
        hook.applyForCTO{value: 0.1 ether}(poolId, newCreator);
        hook.approveCTO(poolId); // hook.owner() == address(this) — deployed directly in setUp(), not pranked
        (, , , address updatedCreator, ,) = hook.pools(poolId);
        assertEq(updatedCreator, newCreator, "CTO must reassign the pool's registered creator");

        SparkGoBurner burner = new SparkGoBurner();
        vm.prank(DEPLOYER);
        launcher.setBurner(address(burner));

        vm.deal(address(this), 1 ether);
        bytes32 burnerSalt = _mineVanitySaltFrom(address(this), 1_000_000);
        SparkGoLauncher.LaunchParams memory bp = SparkGoLauncher.LaunchParams({
            name: "Burn", symbol: "BURN", metaURI: "",
            feeWallet: address(0), positionManager: UNISWAP_V4_POSITION_MANAGER, quoteToken: address(0),
            vanitySalt: burnerSalt, minQuoteOut: 0, minTokensOut: 0, revertOnInstantBuyFailure: true
        });
        (address burnToken,,) = launcher.launch{value: 0.001111 ether + 0.02 ether}(bp);
        V4PoolKey memory burnKey = V4PoolKey({currency0: address(0), currency1: burnToken, fee: 0, tickSpacing: 200, hooks: address(hook)});
        bytes32 burnPoolId = keccak256(abi.encode(burnKey));
        (, , , address burnPoolCreator, ,) = hook.pools(burnPoolId);
        assertEq(burnPoolCreator, address(burner), "feeWallet: address(0) must register the burner as this pool's creator");

        V4Trader burnTrader = new V4Trader(UNISWAP_V4_POOL_MANAGER);
        burnTrader.buy{value: 0.02 ether}(address(hook), burnToken, 0.02 ether);
        vm.roll(startBlock + 30);
        burnTrader.sell(address(hook), burnToken, IERC20(burnToken).balanceOf(address(burnTrader)));
        assertGt(hook.accruedFees(burnPoolId), 0, "fees must have accrued for the burner to claim");

        address burnCaller = address(0xB012);
        vm.prank(burnCaller);
        (uint256 tokenBurned, uint256 callerReward) = burner.burnV4(UNISWAP_V4_POOL_MANAGER, address(hook), burnToken, address(0));

        assertGt(tokenBurned, 0, "burner must have swapped claimed fees into the token and burned some");
        assertGt(callerReward, 0, "burner must have rewarded the caller in native BNB");
        assertEq(burnCaller.balance, callerReward, "reward must have gone to whoever called the burner");
        assertGt(IERC20(burnToken).balanceOf(0x000000000000000000000000000000000000dEaD), 0, "burned tokens must be at the dead address");
    }

    receive() external payable {}

    function _mineHookSalt(address poolManager_, address launcher_, address platformWallet_) internal view returns (bytes32) {
        bytes memory code = abi.encodePacked(type(SparkGoHookV4).creationCode, abi.encode(poolManager_, launcher_, platformWallet_));
        bytes32 initCodeHash = keccak256(code);
        for (uint256 nonce; ; ++nonce) {
            bytes32 salt = bytes32(nonce);
            address predicted = vm.computeCreate2Address(salt, initCodeHash, address(this));
            if (uint160(predicted) & 0x3FFF == 0xC4) return salt;
        }
    }

    function _mineVanitySalt(address creator) internal view returns (bytes32) {
        return _mineVanitySaltFrom(creator, 0);
    }

    function _mineVanitySaltFrom(address creator, uint256 startNonce) internal view returns (bytes32) {
        bytes32 initCodeHash = keccak256(abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", address(tokenImpl), hex"5af43d82803e903d91602b57fd5bf3"
        ));
        for (uint256 nonce = startNonce; ; ++nonce) {
            bytes32 vanitySalt = bytes32(nonce);
            bytes32 actualSalt = keccak256(abi.encode(creator, vanitySalt));
            address predicted = vm.computeCreate2Address(actualSalt, initCodeHash, address(launcher));
            if (uint16(uint160(predicted)) == 0x1111) return vanitySalt;
        }
    }

    function _mineVanitySaltBelow(address creator, address ceiling) internal view returns (bytes32) {
        bytes32 initCodeHash = keccak256(abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", address(tokenImpl), hex"5af43d82803e903d91602b57fd5bf3"
        ));
        for (uint256 nonce; ; ++nonce) {
            bytes32 vanitySalt = bytes32(nonce);
            bytes32 actualSalt = keccak256(abi.encode(creator, vanitySalt));
            address predicted = vm.computeCreate2Address(actualSalt, initCodeHash, address(launcher));
            if (uint16(uint160(predicted)) == 0x1111 && predicted < ceiling) return vanitySalt;
        }
    }
}
