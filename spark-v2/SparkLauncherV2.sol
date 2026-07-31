// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme

struct V4PoolKey {
    address currency0;
    address currency1;
    uint24  fee;
    int24   tickSpacing;
    address hooks;
}

struct V4SwapParams {
    bool    zeroForOne;
    int256  amountSpecified;
    uint160 sqrtPriceLimitX96;
}

struct InfinityPoolKey {
    address currency0;
    address currency1;
    address hooks;
    address poolManager;
    uint24  fee;
    bytes32 parameters;
}

struct InfinitySwapParams {
    bool    zeroForOne;
    int256  amountSpecified;
    uint160 sqrtPriceLimitX96;
}

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

interface IV4PoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(V4PoolKey memory key, V4SwapParams memory params, bytes calldata hookData) external returns (int256);
    function settle() external payable returns (uint256);
    function take(address currency, address to, uint256 amount) external;
}

interface IVault {
    function lock(bytes calldata data) external returns (bytes memory);
    function settle() external payable returns (uint256);
    function take(address currency, address to, uint256 amount) external;
}

interface ICLPoolManagerSwap {
    function swap(InfinityPoolKey memory key, InfinitySwapParams memory params, bytes calldata hookData) external returns (int256);
}

interface IAllowanceTransfer {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface ISparkHookV4 {
    function registerPool(V4PoolKey calldata key, address token, address creator) external;
}

interface ISparkHookInfinity {
    function registerPool(InfinityPoolKey calldata key, address token, address creator) external;
}

contract SparkLauncherV2 {

    error NotOwner();
    error UnsupportedDex();
    error InvalidProtocol();
    error WrongFee();
    error ZeroAddress();
    error ZeroAmount();
    error CloneFailed();
    error PoolAlreadyExists();
    error TransferFailed();
    error ApprovalFailed();
    error InvalidTickRange();
    error InvalidTick(int24 tick);
    error Unauthorized();
    error VanityMismatch();
    error HookRequired();
    error BurnerRequired();

    uint16 public constant VANITY_SUFFIX = 0x1111;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;

    uint24 private constant HOOK_FEE   = 0;
    int24  private constant MIN_TICK     = -887_200;
    int24  private constant MAX_TICK     =  887_200;
    int24  private constant TICK_SPACING =  200;

    uint16 private constant INFINITY_HOOK_BITMAP = 0x8C0;

    uint160 private constant MIN_SQRT_PRICE = 4295128739;
    uint160 private constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;
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

    mapping(address => DexConfig) public dexes;
    mapping(address => address)   public tokenHook;

    address      public immutable tokenImpl;
    ISparkLocker public immutable locker;
    address      public owner;
    address      public launchFeeWallet;
    address      public burner;
    uint256      public launchFee;
    uint256      public marketCapRef = 5e18;

    address private _cbExpected;

    event TokenLaunched(
        address indexed token,
        address indexed creator,
        address indexed positionManager,
        address         feeWallet,
        address         hook,
        bytes32         poolId,
        uint256         tokenId
    );
    event DexAdded(address indexed positionManager, uint8 protocol, address singleton, address poolLogic, address permit2, address hook);
    event DexDisabled(address indexed positionManager);
    event LaunchFeeWalletSet(address indexed wallet);
    event BurnerSet(address indexed burner);
    event LaunchFeeSet(uint256 fee);
    event MarketCapRefSet(uint256 marketCapRef);
    event ETHRescued(address indexed to, uint256 amount);
    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);

    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

    constructor(
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
    ) {
        if (tokenImpl_          == address(0)) revert ZeroAddress();
        if (locker_             == address(0)) revert ZeroAddress();
        if (initialPositionMgr_ == address(0)) revert ZeroAddress();
        if (initialSingleton_   == address(0)) revert ZeroAddress();
        if (initialPermit2_     == address(0)) revert ZeroAddress();
        if (initialProtocol_ > PROTOCOL_PANCAKE_INFINITY) revert InvalidProtocol();
        if (initialProtocol_ == PROTOCOL_PANCAKE_INFINITY && initialPoolLogic_ == address(0)) revert ZeroAddress();
        if (launchFee_          == 0)          revert ZeroAmount();

        owner           = msg.sender;
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
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    function setLaunchFeeWallet(address wallet) external onlyOwner {
        launchFeeWallet = wallet;
        emit LaunchFeeWalletSet(wallet);
    }

    function _launchFeeRecipient() private view returns (address) {
        return launchFeeWallet == address(0) ? owner : launchFeeWallet;
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

    function setMarketCapRef(uint256 ref_) external onlyOwner {
        if (ref_ == 0) revert ZeroAmount();
        marketCapRef = ref_;
        emit MarketCapRefSet(ref_);
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

    function launch(
        string calldata name_,
        string calldata symbol_,
        string calldata metaURI_,
        address         feeWallet_,
        address         positionManager_,
        bytes32         vanitySalt_
    ) external payable returns (address token, bytes32 poolId, uint256 tokenId) {
        token = _deployAndInit(name_, symbol_, metaURI_, vanitySalt_);
        (poolId, tokenId) = _setupAndRegister(token, feeWallet_, positionManager_);
    }

    function _setupAndRegister(
        address token,
        address feeWallet_,
        address positionManager_
    ) private returns (bytes32 poolId, uint256 tokenId) {
        DexConfig storage dex = dexes[positionManager_];
        if (!dex.enabled) revert UnsupportedDex();
        if (dex.hook == address(0)) revert HookRequired();
        if (msg.value < launchFee) revert WrongFee();

        tokenHook[token] = dex.hook;

        (bool feeOk,) = _launchFeeRecipient().call{value: launchFee}("");
        if (!feeOk) revert TransferFailed();
        uint256 extraEth = msg.value - launchFee;

        address effectiveFeeWallet = feeWallet_ == address(0) ? burner : feeWallet_;
        if (effectiveFeeWallet == address(0)) revert BurnerRequired();

        int24 tick;
        if (dex.protocol == PROTOCOL_UNISWAP_V4) {
            (tick, poolId) = _initV4Pool(positionManager_, dex.hook, token, effectiveFeeWallet);
        } else {
            (tick, poolId) = _initInfinityPool(positionManager_, dex.poolLogic, dex.hook, token, effectiveFeeWallet);
        }

        (int24 tickLower, int24 tickUpper, uint128 liquidity) = _computeOneSidedLiquidity(tick);

        ISparkToken(token).setExempt(dex.singleton, true);

        if (dex.protocol == PROTOCOL_UNISWAP_V4) {
            tokenId = _mintV4(positionManager_, dex.hook, dex.permit2, token, tickLower, tickUpper, liquidity, address(locker));
        } else {
            tokenId = _mintInfinity(positionManager_, dex.poolLogic, dex.hook, dex.permit2, token, tickLower, tickUpper, liquidity, address(locker));
        }

        locker.registerPosition(token, tokenId, effectiveFeeWallet, address(0), token, dex.singleton, positionManager_);

        if (extraEth > 0) {
            if (dex.protocol == PROTOCOL_UNISWAP_V4) {
                _instantBuyV4(dex.singleton, dex.hook, token, extraEth, msg.sender);
            } else {
                _instantBuyInfinity(dex.singleton, dex.poolLogic, dex.hook, token, extraEth, msg.sender);
            }
        }

        uint256 creatorTokens = ISparkToken(token).balanceOf(address(this));
        if (creatorTokens > 0) ISparkToken(token).transfer(msg.sender, creatorTokens);
        ISparkToken(token).renounceOwnership();

        emit TokenLaunched(token, msg.sender, positionManager_, effectiveFeeWallet, dex.hook, poolId, tokenId);
    }

    receive() external payable {}

    function _initV4Pool(address positionManager_, address hook_, address token, address creator) private returns (int24 tick, bytes32 poolId) {
        V4PoolKey memory key = V4PoolKey({
            currency0:   address(0),
            currency1:   token,
            fee:         HOOK_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook_
        });
        tick = IV4PositionManager(positionManager_).initializePool(key, _computeSqrtPriceX96());
        if (tick == type(int24).max) revert PoolAlreadyExists();
        poolId = keccak256(abi.encode(key));
        ISparkHookV4(hook_).registerPool(key, token, creator);
    }

    function _initInfinityPool(address positionManager_, address clPoolManager_, address hook_, address token, address creator)
        private returns (int24 tick, bytes32 poolId)
    {
        InfinityPoolKey memory key = InfinityPoolKey({
            currency0:   address(0),
            currency1:   token,
            hooks:       hook_,
            poolManager: clPoolManager_,
            fee:         HOOK_FEE,
            parameters:  _infinityParameters()
        });
        tick = ICLPositionManager(positionManager_).initializePool(key, _computeSqrtPriceX96());
        if (tick == type(int24).max) revert PoolAlreadyExists();
        poolId = keccak256(abi.encode(key));
        ISparkHookInfinity(hook_).registerPool(key, token, creator);
    }

    function _infinityParameters() private pure returns (bytes32) {
        return bytes32((uint256(uint24(TICK_SPACING)) << 16) | INFINITY_HOOK_BITMAP);
    }

    function _computeOneSidedLiquidity(int24 currentTick)
        private pure returns (int24 tickLower, int24 tickUpper, uint128 liquidity)
    {
        tickLower = MIN_TICK;
        tickUpper = _floorToTickSpacing(currentTick);
        if (tickLower >= tickUpper) revert InvalidTickRange();
        liquidity = _getLiquidityForAmount1(MIN_SQRT_PRICE, _getSqrtPriceAtTick(tickUpper), TOTAL_SUPPLY);
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
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        address recipient
    ) private returns (uint256 tokenId) {
        _safeApprove(token, permit2_, TOTAL_SUPPLY);
        IAllowanceTransfer(permit2_).approve(token, positionManager_, uint160(TOTAL_SUPPLY), uint48(block.timestamp + 300));

        V4PoolKey memory key = V4PoolKey({
            currency0:   address(0),
            currency1:   token,
            fee:         HOOK_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook_
        });

        bytes memory actions = abi.encodePacked(uint8(ACTION_MINT_POSITION), uint8(ACTION_SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, tickLower, tickUpper, uint256(liquidity), uint128(TOTAL_SUPPLY), uint128(TOTAL_SUPPLY), recipient, bytes(""));
        params[1] = abi.encode(address(0), token);

        tokenId = IV4PositionManager(positionManager_).nextTokenId();
        IV4PositionManager(positionManager_).modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    function _mintInfinity(
        address positionManager_,
        address clPoolManager_,
        address hook_,
        address permit2_,
        address token,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        address recipient
    ) private returns (uint256 tokenId) {
        _safeApprove(token, permit2_, TOTAL_SUPPLY);
        IAllowanceTransfer(permit2_).approve(token, positionManager_, uint160(TOTAL_SUPPLY), uint48(block.timestamp + 300));

        InfinityPoolKey memory key = InfinityPoolKey({
            currency0:   address(0),
            currency1:   token,
            hooks:       hook_,
            poolManager: clPoolManager_,
            fee:         HOOK_FEE,
            parameters:  _infinityParameters()
        });

        bytes memory actions = abi.encodePacked(uint8(ACTION_MINT_POSITION), uint8(ACTION_SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, tickLower, tickUpper, uint256(liquidity), uint128(TOTAL_SUPPLY), uint128(TOTAL_SUPPLY), recipient, bytes(""));
        params[1] = abi.encode(address(0), token);

        tokenId = ICLPositionManager(positionManager_).nextTokenId();
        ICLPositionManager(positionManager_).modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    function _instantBuyV4(address poolManager_, address hook_, address token, uint256 extraEth, address creator) private {
        _cbExpected = poolManager_;
        IV4PoolManager(poolManager_).unlock(abi.encode(hook_, token, extraEth, creator));
        _cbExpected = address(0);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (_cbExpected == address(0) || msg.sender != _cbExpected) revert Unauthorized();
        (address hook_, address token, uint256 extraEth, address creator) = abi.decode(data, (address, address, uint256, address));

        V4PoolKey memory key = V4PoolKey({
            currency0:   address(0),
            currency1:   token,
            fee:         HOOK_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook_
        });
        int256 delta = IV4PoolManager(msg.sender).swap(
            key,
            V4SwapParams({zeroForOne: true, amountSpecified: -int256(extraEth), sqrtPriceLimitX96: MIN_SQRT_PRICE + 1}),
            ""
        );
        uint256 amountOut = uint256(uint128(int128(delta)));

        IV4PoolManager(msg.sender).settle{value: extraEth}();
        IV4PoolManager(msg.sender).take(token, creator, amountOut);
        return "";
    }

    function _instantBuyInfinity(address vault_, address clPoolManager_, address hook_, address token, uint256 extraEth, address creator) private {
        _cbExpected = vault_;
        IVault(vault_).lock(abi.encode(clPoolManager_, hook_, token, extraEth, creator));
        _cbExpected = address(0);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        if (_cbExpected == address(0) || msg.sender != _cbExpected) revert Unauthorized();
        (address clPoolManager_, address hook_, address token, uint256 extraEth, address creator) =
            abi.decode(data, (address, address, address, uint256, address));

        InfinityPoolKey memory key = InfinityPoolKey({
            currency0:   address(0),
            currency1:   token,
            hooks:       hook_,
            poolManager: clPoolManager_,
            fee:         HOOK_FEE,
            parameters:  _infinityParameters()
        });
        int256 delta = ICLPoolManagerSwap(clPoolManager_).swap(
            key,
            InfinitySwapParams({zeroForOne: true, amountSpecified: -int256(extraEth), sqrtPriceLimitX96: MIN_SQRT_PRICE + 1}),
            ""
        );
        uint256 amountOut = uint256(uint128(int128(delta)));

        IVault(msg.sender).settle{value: extraEth}();
        IVault(msg.sender).take(token, creator, amountOut);
        return "";
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

    function _computeSqrtPriceX96() private view returns (uint160) {
        return _sqrtPriceX96(marketCapRef, TOTAL_SUPPLY);
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

    function _safeApprove(address token_, address spender, uint256 amount) private {
        (bool reset,) = token_.call(abi.encodeWithSelector(0x095ea7b3, spender, 0));
        reset;
        (bool ok, bytes memory data) = token_.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        if (!ok || (data.length > 0 && !abi.decode(data, (bool)))) revert ApprovalFailed();
    }

    function _safeTransfer(address token_, address to, uint256 amount) private {
        if (amount == 0) return;
        (bool ok, bytes memory data) = token_.call(
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        if (!ok || (data.length > 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
