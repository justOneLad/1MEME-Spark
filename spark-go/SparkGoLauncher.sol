// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// SparkGo — currency-general, hook-gated launcher (Uniswap v4 / PancakeSwap
// Infinity singleton pools).
//
// currency0 is whichever of (quoteToken, token) sorts lower, not hardcoded
// address(0) — see _computeOneSidedLiquidity and _swapQuoteToToken.
//
// State variables below must only ever be appended to in future upgrades,
// never reordered or removed.

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../common/SparkRouting.sol";

interface ISparkToken {
    function initSpark(string calldata name_, string calldata symbol_, string calldata metaURI_, address launcher_) external;
    function renounceOwnership() external;
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function setExempt(address account, bool exempt_) external;
}

interface ISparkLocker {
    function registerPosition(
        address token,
        uint256 tokenId,
        address feeWallet,
        address currency0,
        address currency1,
        address singleton,
        address positionManager
    ) external;
}

interface IV4PositionManager {
    function initializePool(V4PoolKey calldata key, uint160 sqrtPriceX96) external payable returns (int24);
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
}

interface ICLPositionManager {
    function initializePool(InfinityPoolKey calldata key, uint160 sqrtPriceX96) external payable returns (int24);
    function modifyLiquidities(bytes calldata payload, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
}

interface IAllowanceTransfer {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface ISparkGoHookV4 {
    function registerPool(V4PoolKey calldata key, address token, address creator) external;
}

interface ISparkGoHookInfinity {
    function registerPool(InfinityPoolKey calldata key, address token, address creator) external;
}

contract SparkGoLauncher is Initializable, UUPSUpgradeable, OwnableUpgradeable, SparkRouting {

    error UnsupportedDex();
    error UnsupportedQuoteToken();
    error InvalidProtocol();
    error WrongFee();
    error ZeroAddress();
    error ZeroAmount();
    error CloneFailed();
    error PoolAlreadyExists();
    error InvalidTickRange();
    error InvalidTick(int24 tick);
    error VanityMismatch();
    error HookRequired();
    error BurnerRequired();
    error InstantBuyFailed();

    uint16 public constant VANITY_SUFFIX = 0x1111;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;

    uint24 private constant HOOK_FEE   = 0;
    int24  private constant MIN_TICK     = -887_200;
    int24  private constant MAX_TICK     =  887_200;
    int24  private constant TICK_SPACING =  200;

    uint16 private constant INFINITY_HOOK_BITMAP = 0x8C0;

    uint256 private constant Q96 = 0x1000000000000000000000000;

    uint8 public constant PROTOCOL_UNISWAP_V4      = 0;
    uint8 public constant PROTOCOL_PANCAKE_INFINITY = 1;

    uint256 private constant ACTION_MINT_POSITION = 0x02;
    uint256 private constant ACTION_SETTLE_PAIR   = 0x0d;

    struct DexConfig {
        uint8   protocol;
        address singleton;
        address poolLogic;
        address permit2;
        address hook;
        bool    enabled;
    }

    struct QuoteToken {
        uint256 marketCapRef;
        bool    enabled;
    }

    struct LaunchParams {
        string  name;
        string  symbol;
        string  metaURI;
        address feeWallet;
        address positionManager;
        address quoteToken;                  // address(0) = native BNB, matches today's behavior
        bytes32 vanitySalt;
        uint256 minQuoteOut;                 // leg 1 (native -> quoteToken via fallback routes) slippage floor; 0 = no check
        uint256 minTokensOut;                // leg 2 (quoteToken -> new token) slippage floor; 0 = no check
        bool    revertOnInstantBuyFailure;    // true = revert whole launch() if instant-buy fails; false = skip + refund
    }

    mapping(address => DexConfig)  public dexes;
    mapping(address => address)    public tokenHook;
    mapping(address => QuoteToken) public quoteTokens;

    address      public weth; // used only to wrap native for V3_STYLE/V2_STYLE fallback routes (see _weth())
    address      public tokenImpl;
    ISparkLocker public locker;
    address      public launchFeeWallet;
    address      public burner;
    uint256      public launchFee;

    event TokenLaunched(
        address indexed token,
        address indexed creator,
        address indexed positionManager,
        address         quoteToken,
        address         feeWallet,
        address         hook,
        bytes32         poolId,
        uint256         tokenId
    );
    event DexAdded(address indexed positionManager, uint8 protocol, address singleton, address poolLogic, address permit2, address hook);
    event DexDisabled(address indexed positionManager);
    event QuoteTokenAdded(address indexed token, uint256 marketCapRef);
    event QuoteTokenDisabled(address indexed token);
    event LaunchFeeWalletSet(address indexed wallet);
    event BurnerSet(address indexed burner);
    event LaunchFeeSet(uint256 fee);
    event MarketCapRefSet(address indexed token, uint256 marketCapRef);
    event ETHRescued(address indexed to, uint256 amount);
    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);
    event InstantBuySkipped(address indexed token, uint256 refundedWei);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address weth_,
        address tokenImpl_,
        address locker_,
        address launchFeeWallet_,
        address initialPositionMgr_,
        uint8   initialProtocol_,
        address initialSingleton_,
        address initialPoolLogic_,
        address initialPermit2_,
        address initialHook_,
        uint256 launchFee_
    ) external initializer {
        if (weth_               == address(0)) revert ZeroAddress();
        if (tokenImpl_          == address(0)) revert ZeroAddress();
        if (locker_             == address(0)) revert ZeroAddress();
        if (initialPositionMgr_ == address(0)) revert ZeroAddress();
        if (initialSingleton_   == address(0)) revert ZeroAddress();
        if (initialPermit2_     == address(0)) revert ZeroAddress();
        if (initialProtocol_ > PROTOCOL_PANCAKE_INFINITY) revert InvalidProtocol();
        if (initialProtocol_ == PROTOCOL_PANCAKE_INFINITY && initialPoolLogic_ == address(0)) revert ZeroAddress();
        if (launchFee_          == 0)          revert ZeroAmount();

        __Ownable_init(msg.sender);

        weth            = weth_;
        tokenImpl       = tokenImpl_;
        locker          = ISparkLocker(locker_);
        launchFeeWallet = launchFeeWallet_;
        launchFee       = launchFee_;

        dexes[initialPositionMgr_] = DexConfig({
            protocol:  initialProtocol_,
            singleton: initialSingleton_,
            poolLogic: initialPoolLogic_,
            permit2:   initialPermit2_,
            hook:      initialHook_,
            enabled:   true
        });
        emit DexAdded(initialPositionMgr_, initialProtocol_, initialSingleton_, initialPoolLogic_, initialPermit2_, initialHook_);

        quoteTokens[address(0)] = QuoteToken({marketCapRef: 5e18, enabled: true});
        emit QuoteTokenAdded(address(0), 5e18);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _weth() internal view override returns (address) {
        return weth;
    }

    function setRoutes(address quoteToken_, Route[] calldata routes_) external onlyOwner {
        _setRoutes(quoteToken_, routes_);
    }

    function setLaunchFeeWallet(address wallet) external onlyOwner {
        launchFeeWallet = wallet;
        emit LaunchFeeWalletSet(wallet);
    }

    function _launchFeeRecipient() private view returns (address) {
        return launchFeeWallet == address(0) ? owner() : launchFeeWallet;
    }

    function setBurner(address burner_) external onlyOwner {
        burner = burner_;
        emit BurnerSet(burner_);
    }

    function setLaunchFee(uint256 fee_) external onlyOwner {
        if (fee_ == 0) revert ZeroAmount();
        launchFee = fee_;
        emit LaunchFeeSet(fee_);
    }

    function setMarketCapRef(address token_, uint256 ref_) external onlyOwner {
        if (!quoteTokens[token_].enabled) revert UnsupportedQuoteToken();
        if (ref_ == 0) revert ZeroAmount();
        quoteTokens[token_].marketCapRef = ref_;
        emit MarketCapRefSet(token_, ref_);
    }

    function addQuoteToken(address token_, uint256 marketCapRef_) external onlyOwner {
        if (marketCapRef_ == 0) revert ZeroAmount();
        quoteTokens[token_] = QuoteToken({marketCapRef: marketCapRef_, enabled: true});
        emit QuoteTokenAdded(token_, marketCapRef_);
    }

    function disableQuoteToken(address token_) external onlyOwner {
        if (!quoteTokens[token_].enabled) revert UnsupportedQuoteToken();
        quoteTokens[token_].enabled = false;
        emit QuoteTokenDisabled(token_);
    }

    function addDex(
        address positionManager_,
        uint8   protocol_,
        address singleton_,
        address poolLogic_,
        address permit2_,
        address hook_
    ) external onlyOwner {
        if (positionManager_ == address(0)) revert ZeroAddress();
        if (singleton_        == address(0)) revert ZeroAddress();
        if (permit2_          == address(0)) revert ZeroAddress();
        if (protocol_ > PROTOCOL_PANCAKE_INFINITY) revert InvalidProtocol();
        if (protocol_ == PROTOCOL_PANCAKE_INFINITY && poolLogic_ == address(0)) revert ZeroAddress();
        dexes[positionManager_] = DexConfig({
            protocol:  protocol_,
            singleton: singleton_,
            poolLogic: poolLogic_,
            permit2:   permit2_,
            hook:      hook_,
            enabled:   true
        });
        emit DexAdded(positionManager_, protocol_, singleton_, poolLogic_, permit2_, hook_);
    }

    function disableDex(address positionManager_) external onlyOwner {
        if (!dexes[positionManager_].enabled) revert UnsupportedDex();
        dexes[positionManager_].enabled = false;
        emit DexDisabled(positionManager_);
    }

    function rescueETH(address to_, uint256 amount_) external onlyOwner {
        if (to_     == address(0)) revert ZeroAddress();
        if (amount_ == 0)         revert ZeroAmount();
        (bool ok,) = to_.call{value: amount_}("");
        if (!ok) revert TransferFailed();
        emit ETHRescued(to_, amount_);
    }

    function rescueERC20(address token_, address to_, uint256 amount_) external onlyOwner {
        if (token_  == address(0)) revert ZeroAddress();
        if (to_     == address(0)) revert ZeroAddress();
        if (amount_ == 0)         revert ZeroAmount();
        _safeTransfer(token_, to_, amount_);
        emit ERC20Rescued(token_, to_, amount_);
    }

    function launch(LaunchParams calldata p) external payable returns (address token, bytes32 poolId, uint256 tokenId) {
        token = _deployAndInit(p.name, p.symbol, p.metaURI, p.vanitySalt);
        (poolId, tokenId) = _setupAndRegister(token, p);
    }

    function _setupAndRegister(
        address token,
        LaunchParams calldata p
    ) private returns (bytes32 poolId, uint256 tokenId) {
        DexConfig storage dex = dexes[p.positionManager];
        if (!dex.enabled) revert UnsupportedDex();
        if (dex.hook == address(0)) revert HookRequired();
        if (!quoteTokens[p.quoteToken].enabled) revert UnsupportedQuoteToken();
        if (msg.value < launchFee) revert WrongFee();

        tokenHook[token] = dex.hook;

        (bool feeOk,) = _launchFeeRecipient().call{value: launchFee}("");
        if (!feeOk) revert TransferFailed();
        uint256 extraEth = msg.value - launchFee;

        address effectiveFeeWallet = p.feeWallet == address(0) ? burner : p.feeWallet;
        if (effectiveFeeWallet == address(0)) revert BurnerRequired();

        bool tokenIsCurrency1 = token > p.quoteToken;
        int24 tick;
        if (dex.protocol == PROTOCOL_UNISWAP_V4) {
            (tick, poolId) = _initV4Pool(p.positionManager, dex.hook, token, p.quoteToken, effectiveFeeWallet);
        } else {
            (tick, poolId) = _initInfinityPool(p.positionManager, dex.poolLogic, dex.hook, token, p.quoteToken, effectiveFeeWallet);
        }

        (int24 tickLower, int24 tickUpper, uint128 liquidity) = _computeOneSidedLiquidity(tick, tokenIsCurrency1);

        ISparkToken(token).setExempt(dex.singleton, true);

        if (dex.protocol == PROTOCOL_UNISWAP_V4) {
            tokenId = _mintV4(p.positionManager, dex.hook, dex.permit2, token, p.quoteToken, tickLower, tickUpper, liquidity, address(locker));
        } else {
            tokenId = _mintInfinity(p.positionManager, dex.poolLogic, dex.hook, dex.permit2, token, p.quoteToken, tickLower, tickUpper, liquidity, address(locker));
        }

        locker.registerPosition(token, tokenId, effectiveFeeWallet, p.quoteToken, token, dex.singleton, p.positionManager);

        if (extraEth > 0) {
            try this.instantBuy{value: extraEth}(
                p.quoteToken, token, extraEth, p.minQuoteOut, p.minTokensOut,
                dex.protocol, dex.singleton, dex.poolLogic, dex.hook, msg.sender
            ) {} catch {
                if (p.revertOnInstantBuyFailure) revert InstantBuyFailed();
                (bool refundOk,) = msg.sender.call{value: extraEth}("");
                if (!refundOk) revert TransferFailed();
                emit InstantBuySkipped(token, extraEth);
            }
        }

        uint256 creatorTokens = ISparkToken(token).balanceOf(address(this));
        if (creatorTokens > 0) ISparkToken(token).transfer(msg.sender, creatorTokens);
        ISparkToken(token).renounceOwnership();

        emit TokenLaunched(token, msg.sender, p.positionManager, p.quoteToken, effectiveFeeWallet, dex.hook, poolId, tokenId);
    }

    receive() external payable {}

    function _initV4Pool(address positionManager_, address hook_, address token, address quoteToken_, address creator)
        private returns (int24 tick, bytes32 poolId)
    {
        (address c0, address c1) = token < quoteToken_ ? (token, quoteToken_) : (quoteToken_, token);
        V4PoolKey memory key = V4PoolKey({
            currency0:   c0,
            currency1:   c1,
            fee:         HOOK_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook_
        });
        tick = IV4PositionManager(positionManager_).initializePool(key, _computeSqrtPriceX96(token, quoteToken_));
        if (tick == type(int24).max) revert PoolAlreadyExists();
        poolId = keccak256(abi.encode(key));
        ISparkGoHookV4(hook_).registerPool(key, token, creator);
    }

    function _initInfinityPool(address positionManager_, address clPoolManager_, address hook_, address token, address quoteToken_, address creator)
        private returns (int24 tick, bytes32 poolId)
    {
        (address c0, address c1) = token < quoteToken_ ? (token, quoteToken_) : (quoteToken_, token);
        InfinityPoolKey memory key = InfinityPoolKey({
            currency0:   c0,
            currency1:   c1,
            hooks:       hook_,
            poolManager: clPoolManager_,
            fee:         HOOK_FEE,
            parameters:  _infinityParameters()
        });
        tick = ICLPositionManager(positionManager_).initializePool(key, _computeSqrtPriceX96(token, quoteToken_));
        if (tick == type(int24).max) revert PoolAlreadyExists();
        poolId = keccak256(abi.encode(key));
        ISparkGoHookInfinity(hook_).registerPool(key, token, creator);
    }

    function _infinityParameters() private pure returns (bytes32) {
        return bytes32((uint256(uint24(TICK_SPACING)) << 16) | INFINITY_HOOK_BITMAP);
    }

    function _computeOneSidedLiquidity(int24 currentTick, bool tokenIsCurrency1)
        private pure returns (int24 tickLower, int24 tickUpper, uint128 liquidity)
    {
        if (tokenIsCurrency1) {
            tickLower = MIN_TICK;
            tickUpper = _floorToTickSpacing(currentTick);
            if (tickLower >= tickUpper) revert InvalidTickRange();
            liquidity = _getLiquidityForAmount1(ROUTING_MIN_SQRT_PRICE, _getSqrtPriceAtTick(tickUpper), TOTAL_SUPPLY);
        } else {
            tickLower = _floorToTickSpacing(currentTick) + TICK_SPACING;
            tickUpper = MAX_TICK;
            if (tickLower >= tickUpper) revert InvalidTickRange();
            liquidity = _getLiquidityForAmount0(_getSqrtPriceAtTick(tickLower), ROUTING_MAX_SQRT_PRICE, TOTAL_SUPPLY);
        }
    }

    function _floorToTickSpacing(int24 tick) private pure returns (int24) {
        int24 compressed = tick / TICK_SPACING;
        if (tick < 0 && tick % TICK_SPACING != 0) compressed--;
        return compressed * TICK_SPACING;
    }

    function _mintV4(
        address positionManager_,
        address hook_,
        address permit2_,
        address token,
        address quoteToken_,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        address recipient
    ) private returns (uint256 tokenId) {
        _safeApprove(token, permit2_, TOTAL_SUPPLY);
        IAllowanceTransfer(permit2_).approve(token, positionManager_, uint160(TOTAL_SUPPLY), uint48(block.timestamp + 300));

        (address c0, address c1) = token < quoteToken_ ? (token, quoteToken_) : (quoteToken_, token);
        V4PoolKey memory key = V4PoolKey({
            currency0:   c0,
            currency1:   c1,
            fee:         HOOK_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook_
        });

        bytes memory actions = abi.encodePacked(uint8(ACTION_MINT_POSITION), uint8(ACTION_SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, tickLower, tickUpper, uint256(liquidity), uint128(TOTAL_SUPPLY), uint128(TOTAL_SUPPLY), recipient, bytes(""));
        params[1] = abi.encode(c0, c1);

        tokenId = IV4PositionManager(positionManager_).nextTokenId();
        IV4PositionManager(positionManager_).modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    function _mintInfinity(
        address positionManager_,
        address clPoolManager_,
        address hook_,
        address permit2_,
        address token,
        address quoteToken_,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        address recipient
    ) private returns (uint256 tokenId) {
        _safeApprove(token, permit2_, TOTAL_SUPPLY);
        IAllowanceTransfer(permit2_).approve(token, positionManager_, uint160(TOTAL_SUPPLY), uint48(block.timestamp + 300));

        (address c0, address c1) = token < quoteToken_ ? (token, quoteToken_) : (quoteToken_, token);
        InfinityPoolKey memory key = InfinityPoolKey({
            currency0:   c0,
            currency1:   c1,
            hooks:       hook_,
            poolManager: clPoolManager_,
            fee:         HOOK_FEE,
            parameters:  _infinityParameters()
        });

        bytes memory actions = abi.encodePacked(uint8(ACTION_MINT_POSITION), uint8(ACTION_SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, tickLower, tickUpper, uint256(liquidity), uint128(TOTAL_SUPPLY), uint128(TOTAL_SUPPLY), recipient, bytes(""));
        params[1] = abi.encode(c0, c1);

        tokenId = ICLPositionManager(positionManager_).nextTokenId();
        ICLPositionManager(positionManager_).modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    function instantBuy(
        address quoteToken_,
        address token_,
        uint256 extraEth_,
        uint256 minQuoteOut_,
        uint256 minTokensOut_,
        uint8   protocol_,
        address singleton_,
        address poolLogic_,
        address hook_,
        address recipient_
    ) external payable {
        if (msg.sender != address(this)) revert Unauthorized();

        uint256 quoteAmount = extraEth_;
        if (quoteToken_ != address(0)) {
            bool ok;
            (quoteAmount, ok) = _acquireQuoteToken(quoteToken_, extraEth_, minQuoteOut_, address(this));
            if (!ok) revert InstantBuyFailed();
        }

        uint256 tokensOut = _swapQuoteToToken(protocol_, singleton_, poolLogic_, hook_, quoteToken_, token_, quoteAmount, minTokensOut_, recipient_);
        if (tokensOut < minTokensOut_) revert InstantBuyFailed();
    }

    function _swapQuoteToToken(
        uint8   protocol_,
        address singleton_,
        address poolLogic_,
        address hook_,
        address quoteToken_,
        address token_,
        uint256 amountIn_,
        uint256 minOut_,
        address recipient_
    ) private returns (uint256 amountOut) {
        if (protocol_ == PROTOCOL_UNISWAP_V4) {
            amountOut = _executeV4Swap(singleton_, hook_, HOOK_FEE, TICK_SPACING, quoteToken_, token_, amountIn_, minOut_, recipient_);
        } else {
            amountOut = _executeInfinitySwap(singleton_, poolLogic_, hook_, HOOK_FEE, _infinityParameters(), quoteToken_, token_, amountIn_, minOut_, recipient_);
        }
    }

    function _deployAndInit(
        string calldata name_,
        string calldata symbol_,
        string calldata metaURI_,
        bytes32         vanitySalt_
    ) private returns (address token) {
        bytes32 salt = keccak256(abi.encode(msg.sender, vanitySalt_));
        token = _clone(tokenImpl, salt);
        if (uint16(uint160(token)) != VANITY_SUFFIX) revert VanityMismatch();
        ISparkToken(token).initSpark(name_, symbol_, metaURI_, address(this));
    }

    function _clone(address impl, bytes32 salt) private returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, impl))
            mstore(add(ptr, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
        }
        if (instance == address(0)) revert CloneFailed();
    }

    function _computeSqrtPriceX96(address sparkToken, address quoteToken_) private view returns (uint160) {
        uint256 marketCapRef_ = quoteTokens[quoteToken_].marketCapRef;
        if (sparkToken < quoteToken_) {
            return _sqrtPriceX96(TOTAL_SUPPLY, marketCapRef_);
        } else {
            return _sqrtPriceX96(marketCapRef_, TOTAL_SUPPLY);
        }
    }

    function _sqrtPriceX96(uint256 amount0, uint256 amount1) private pure returns (uint160) {
        uint256 scaled = (amount1 << 96) / amount0;
        return uint160(_sqrt(scaled) << 48);
    }

    function _sqrt(uint256 x) private pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (x + 1) >> 1;
        while (z < y) { y = z; z = (x / z + z) >> 1; }
    }

    function _getSqrtPriceAtTick(int24 tick) private pure returns (uint160 sqrtPriceX96) {
        unchecked {
            uint256 absTick;
            assembly ("memory-safe") {
                tick := signextend(2, tick)
                let mask := sar(255, tick)
                absTick := xor(mask, add(mask, tick))
            }
            if (absTick > uint256(int256(MAX_TICK))) revert InvalidTick(tick);

            uint256 price;
            assembly ("memory-safe") {
                price := xor(shl(128, 1), mul(xor(shl(128, 1), 0xfffcb933bd6fad37aa2d162d1a594001), and(absTick, 0x1)))
            }
            if (absTick & 0x2 != 0) price = (price * 0xfff97272373d413259a46990580e213a) >> 128;
            if (absTick & 0x4 != 0) price = (price * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x8 != 0) price = (price * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x10 != 0) price = (price * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x20 != 0) price = (price * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x40 != 0) price = (price * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x80 != 0) price = (price * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x100 != 0) price = (price * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x200 != 0) price = (price * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x400 != 0) price = (price * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x800 != 0) price = (price * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x1000 != 0) price = (price * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x2000 != 0) price = (price * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x4000 != 0) price = (price * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x8000 != 0) price = (price * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x10000 != 0) price = (price * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
            if (absTick & 0x20000 != 0) price = (price * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x40000 != 0) price = (price * 0x2216e584f5fa1ea926041bedfe98) >> 128;
            if (absTick & 0x80000 != 0) price = (price * 0x48a170391f7dc42444e8fa2) >> 128;

            assembly ("memory-safe") {
                if sgt(tick, 0) { price := div(not(0), price) }
                sqrtPriceX96 := shr(32, add(price, sub(shl(32, 1), 1)))
            }
        }
    }

    function _getLiquidityForAmount1(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1)
        private pure returns (uint128)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        return uint128(_mulDiv(amount1, Q96, sqrtPriceBX96 - sqrtPriceAX96));
    }

    function _getLiquidityForAmount0(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0)
        private pure returns (uint128)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        uint256 intermediate = _mulDiv(uint256(sqrtPriceAX96), uint256(sqrtPriceBX96), Q96);
        return uint128(_mulDiv(amount0, intermediate, sqrtPriceBX96 - sqrtPriceAX96));
    }

    function _mulDiv(uint256 a, uint256 b, uint256 denominator) private pure returns (uint256 result) {
        unchecked {
            uint256 prod0 = a * b;
            uint256 prod1;
            assembly ("memory-safe") {
                let mm := mulmod(a, b, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            require(denominator > prod1);

            if (prod1 == 0) {
                assembly ("memory-safe") {
                    result := div(prod0, denominator)
                }
                return result;
            }

            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(a, b, denominator)
            }
            assembly ("memory-safe") {
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = (0 - denominator) & denominator;
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
            }
            assembly ("memory-safe") {
                prod0 := div(prod0, twos)
            }
            assembly ("memory-safe") {
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            uint256 inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;

            result = prod0 * inv;
            return result;
        }
    }
}
