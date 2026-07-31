// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme

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
        address token0,
        address token1,
        address pool,
        address positionManager
    ) external;
}

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24   tick,
        uint16  observationIndex,
        uint16  observationCardinality,
        uint16  observationCardinalityNext,
        uint32  feeProtocol,
        bool    unlocked
    );
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    function mint(MintParams calldata params)
        external payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IWETH {
    function deposit() external payable;
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes   path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params)
        external payable returns (uint256 amountOut);
}

contract SparkLauncher {

    error NotOwner();
    error UnsupportedQuoteToken();
    error UnsupportedDex();
    error WrongFee();
    error ZeroAddress();
    error ZeroAmount();
    error CloneFailed();
    error PoolAlreadyExists();
    error TransferFailed();
    error ApprovalFailed();
    error InvalidTickRange();

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;

    uint24 private constant FEE_TIER     = 10_000;
    int24  private constant MIN_TICK     = -887_200;
    int24  private constant MAX_TICK     =  887_200;
    int24  private constant TICK_SPACING =  200;

    struct DexConfig {
        address positionManager;
        address router;
        bool    enabled;
    }

    struct QuoteToken {
        uint256 marketCapRef;
        uint24  wethPairFee;
        bool    enabled;
    }

    mapping(address => DexConfig)  public dexes;
    mapping(address => QuoteToken) public quoteTokens;

    address      public immutable weth;
    address      public immutable tokenImpl;
    ISparkLocker public immutable locker;
    address      public owner;
    address      public launchFeeWallet;
    uint256      public launchFee;

    event TokenLaunched(
        address indexed token,
        address indexed creator,
        address indexed factory,
        address         quoteToken,
        address         feeWallet,
        address         pool,
        uint256         tokenId
    );
    event DexAdded(address indexed factory, address positionManager, address router);
    event DexDisabled(address indexed factory);
    event QuoteTokenAdded(address indexed token, uint256 marketCapRef, uint24 wethPairFee);
    event QuoteTokenDisabled(address indexed token);
    event LaunchFeeWalletSet(address indexed wallet);
    event LaunchFeeSet(uint256 fee);
    event MarketCapRefSet(address indexed token, uint256 marketCapRef);
    event ETHRescued(address indexed to, uint256 amount);
    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);

    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

    constructor(
        address weth_,
        address tokenImpl_,
        address locker_,
        address launchFeeWallet_,
        address initialFactory_,
        address initialPositionMgr_,
        address initialRouter_,
        uint256 launchFee_
    ) {
        if (weth_               == address(0)) revert ZeroAddress();
        if (tokenImpl_          == address(0)) revert ZeroAddress();
        if (locker_             == address(0)) revert ZeroAddress();
        if (initialFactory_     == address(0)) revert ZeroAddress();
        if (initialPositionMgr_ == address(0)) revert ZeroAddress();
        if (initialRouter_      == address(0)) revert ZeroAddress();
        if (launchFee_          == 0)          revert ZeroAmount();

        owner           = msg.sender;
        weth            = weth_;
        tokenImpl       = tokenImpl_;
        locker          = ISparkLocker(locker_);
        launchFeeWallet = launchFeeWallet_;
        launchFee       = launchFee_;

        dexes[initialFactory_] = DexConfig({
            positionManager: initialPositionMgr_,
            router:          initialRouter_,
            enabled:         true
        });
        emit DexAdded(initialFactory_, initialPositionMgr_, initialRouter_);

        quoteTokens[weth_] = QuoteToken({
            marketCapRef: 5e18,
            wethPairFee:  0,
            enabled:      true
        });
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

    function addDex(address factory_, address positionMgr_, address router_) external onlyOwner {
        if (factory_     == address(0)) revert ZeroAddress();
        if (positionMgr_ == address(0)) revert ZeroAddress();
        if (router_      == address(0)) revert ZeroAddress();
        dexes[factory_] = DexConfig({
            positionManager: positionMgr_,
            router:          router_,
            enabled:         true
        });
        emit DexAdded(factory_, positionMgr_, router_);
    }

    function disableDex(address factory_) external onlyOwner {
        if (!dexes[factory_].enabled) revert UnsupportedDex();
        dexes[factory_].enabled = false;
        emit DexDisabled(factory_);
    }

    function addQuoteToken(
        address token_,
        uint256 marketCapRef_,
        uint24  wethPairFee_
    ) external onlyOwner {
        if (token_        == address(0)) revert ZeroAddress();
        if (marketCapRef_ == 0)          revert ZeroAmount();
        if (token_ != weth && wethPairFee_ == 0) revert ZeroAmount();
        quoteTokens[token_] = QuoteToken({
            marketCapRef: marketCapRef_,
            wethPairFee:  wethPairFee_,
            enabled:      true
        });
        emit QuoteTokenAdded(token_, marketCapRef_, wethPairFee_);
    }

    function disableQuoteToken(address token_) external onlyOwner {
        if (!quoteTokens[token_].enabled) revert UnsupportedQuoteToken();
        quoteTokens[token_].enabled = false;
        emit QuoteTokenDisabled(token_);
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
        address         factory_,
        address         quoteToken_
    ) external payable returns (address token, address pool, uint256 tokenId) {
        token = _deployAndInit(name_, symbol_, metaURI_);
        (pool, tokenId) = _setupAndRegister(token, feeWallet_, factory_, quoteToken_);
    }

    function _setupAndRegister(
        address token,
        address feeWallet_,
        address factory_,
        address quoteToken_
    ) private returns (address pool, uint256 tokenId) {
        if (!dexes[factory_].enabled)          revert UnsupportedDex();
        if (!quoteTokens[quoteToken_].enabled)  revert UnsupportedQuoteToken();
        if (msg.value < launchFee)              revert WrongFee();

        (bool feeOk,) = _launchFeeRecipient().call{value: launchFee}("");
        if (!feeOk) revert TransferFailed();
        uint256 extraEth = msg.value - launchFee;

        (address token0, address token1) = token < quoteToken_
            ? (token,       quoteToken_)
            : (quoteToken_, token      );

        address existingPool = IUniswapV3Factory(factory_).getPool(token0, token1, FEE_TIER);
        if (existingPool == address(0)) {
            pool = IUniswapV3Factory(factory_).createPool(token0, token1, FEE_TIER);
        } else {
            (uint160 existingPrice,,,,,,) = IUniswapV3Pool(existingPool).slot0();
            if (existingPrice != 0) revert PoolAlreadyExists();
            pool = existingPool;
        }

        ISparkToken(token).setExempt(pool, true);

        IUniswapV3Pool(pool).initialize(
            _computeSqrtPriceX96(token, quoteToken_, quoteTokens[quoteToken_].marketCapRef)
        );

        tokenId = _mintAndRegister(
            dexes[factory_].positionManager,
            token,
            feeWallet_ == address(0) ? msg.sender : feeWallet_,
            token0, token1, pool
        );

        if (extraEth > 0) {
            _doInstantBuy(dexes[factory_].router, quoteToken_, token, extraEth, quoteTokens[quoteToken_].wethPairFee);
        }

        uint256 creatorTokens = ISparkToken(token).balanceOf(address(this));
        if (creatorTokens > 0) ISparkToken(token).transfer(msg.sender, creatorTokens);

        ISparkToken(token).renounceOwnership();

        emit TokenLaunched(
            token, msg.sender, factory_, quoteToken_,
            feeWallet_ == address(0) ? msg.sender : feeWallet_,
            pool, tokenId
        );
    }

    receive() external payable {}

    function _doInstantBuy(
        address router_,
        address quoteToken_,
        address token,
        uint256 extraEth,
        uint24  wethPairFee
    ) private {
        IWETH(weth).deposit{value: extraEth}();
        _safeApprove(weth, router_, extraEth);

        if (quoteToken_ == weth) {
            ISwapRouter(router_).exactInputSingle(ISwapRouter.ExactInputSingleParams({
                tokenIn:           weth,
                tokenOut:          token,
                fee:               FEE_TIER,
                recipient:         msg.sender,
                amountIn:          extraEth,
                amountOutMinimum:  0,
                sqrtPriceLimitX96: 0
            }));
        } else {
            ISwapRouter(router_).exactInput(ISwapRouter.ExactInputParams({
                path:             abi.encodePacked(weth, wethPairFee, quoteToken_, FEE_TIER, token),
                recipient:        msg.sender,
                amountIn:         extraEth,
                amountOutMinimum: 0
            }));
        }
    }

    function _mintAndRegister(
        address positionManager_,
        address token,
        address feeWallet,
        address token0,
        address token1,
        address pool
    ) private returns (uint256 tokenId) {
        {
            int24   currentTick;
            int24   tickLower;
            int24   tickUpper;
            uint256 amount0Desired;
            uint256 amount1Desired;

            (, currentTick,,,,,) = IUniswapV3Pool(pool).slot0();

            if (token == token0) {
                tickLower      = _floorToTickSpacing(currentTick) + TICK_SPACING;
                tickUpper      = MAX_TICK;
                amount0Desired = TOTAL_SUPPLY;
                amount1Desired = 0;
            } else {
                tickLower      = MIN_TICK;
                tickUpper      = _floorToTickSpacing(currentTick);
                amount0Desired = 0;
                amount1Desired = TOTAL_SUPPLY;
            }
            if (tickLower >= tickUpper) revert InvalidTickRange();

            _safeApprove(token, positionManager_, TOTAL_SUPPLY);

            (tokenId,,,) = INonfungiblePositionManager(positionManager_).mint(
                INonfungiblePositionManager.MintParams({
                    token0:         token0,
                    token1:         token1,
                    fee:            FEE_TIER,
                    tickLower:      tickLower,
                    tickUpper:      tickUpper,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min:     0,
                    amount1Min:     0,
                    recipient:      address(locker),
                    deadline:       block.timestamp
                })
            );
        }

        locker.registerPosition(token, tokenId, feeWallet, token0, token1, pool, positionManager_);
    }

    function _deployAndInit(
        string calldata name_,
        string calldata symbol_,
        string calldata metaURI_
    ) private returns (address token) {
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, block.timestamp, name_, symbol_, metaURI_));
        token = _clone(tokenImpl, salt);
        ISparkToken(token).initSpark(name_, symbol_, metaURI_, address(this));
    }

    function _computeSqrtPriceX96(address sparkToken, address quoteToken_, uint256 marketCapRef_)
        private pure returns (uint160)
    {
        if (sparkToken < quoteToken_) {
            return _sqrtPriceX96(TOTAL_SUPPLY, marketCapRef_);
        } else {
            return _sqrtPriceX96(marketCapRef_, TOTAL_SUPPLY);
        }
    }

    function _floorToTickSpacing(int24 tick) private pure returns (int24) {
        int24 compressed = tick / TICK_SPACING;
        if (tick < 0 && tick % TICK_SPACING != 0) compressed--;
        return compressed * TICK_SPACING;
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
