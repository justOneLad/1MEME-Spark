// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// SparkLauncher — upgradeable, plain Uniswap V3 / PancakeSwap V3 launcher.
// Storage below is append-only across upgrades.

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SparkRouting, Route} from "../common/SparkRouting.sol";

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

interface IWETHLocal {
    function deposit() external payable;
}

interface ISwapRouterLocal {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IV3SwapRouterNoDeadlineLocal {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract SparkLauncher is Initializable, UUPSUpgradeable, OwnableUpgradeable, SparkRouting {

    error UnsupportedQuoteToken();
    error UnsupportedDex();
    error WrongFee();
    error ZeroAddress();
    error ZeroAmount();
    error CloneFailed();
    error PoolAlreadyExists();
    error InvalidTickRange();
    error VanityMismatch();
    error InstantBuyFailed();

    uint16 public constant VANITY_SUFFIX = 0x1111;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;

    uint24 private constant FEE_TIER     = 10_000;
    int24  private constant MIN_TICK     = -887_200;
    int24  private constant MAX_TICK     =  887_200;
    int24  private constant TICK_SPACING =  200;

    struct DexConfig {
        address positionManager;
        address router;
        bool    routerNoDeadline; // no `deadline` field
        bool    enabled;
    }

    struct QuoteToken {
        uint256 marketCapRef;
        uint24  wethPairFee; // legacy, unused by routing
        bool    enabled;
    }

    struct LaunchParams {
        string  name;
        string  symbol;
        string  metaURI;
        address feeWallet;
        address factory;
        address quoteToken;
        bytes32 vanitySalt;
        uint256 minQuoteOut;                // leg 1 slippage floor; 0 = no check
        uint256 minTokensOut;                // leg 2 slippage floor; 0 = no check
        bool    revertOnInstantBuyFailure;   // false = skip + refund instead of reverting
    }

    mapping(address => DexConfig)  public dexes;
    mapping(address => QuoteToken) public quoteTokens;

    address      public weth;
    address      public tokenImpl;
    ISparkLocker public locker;
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
    event DexAdded(address indexed factory, address positionManager, address router, bool routerNoDeadline);
    event DexDisabled(address indexed factory);
    event QuoteTokenAdded(address indexed token, uint256 marketCapRef, uint24 wethPairFee);
    event QuoteTokenDisabled(address indexed token);
    event LaunchFeeWalletSet(address indexed wallet);
    event LaunchFeeSet(uint256 fee);
    event TokenImplSet(address indexed tokenImpl);
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
        address initialFactory_,
        address initialPositionMgr_,
        address initialRouter_,
        bool    initialRouterNoDeadline_,
        uint256 launchFee_
    ) external initializer {
        if (weth_               == address(0)) revert ZeroAddress();
        if (tokenImpl_          == address(0)) revert ZeroAddress();
        if (locker_             == address(0)) revert ZeroAddress();
        if (initialFactory_     == address(0)) revert ZeroAddress();
        if (initialPositionMgr_ == address(0)) revert ZeroAddress();
        if (initialRouter_      == address(0)) revert ZeroAddress();
        if (launchFee_          == 0)          revert ZeroAmount();

        __Ownable_init(msg.sender);

        weth            = weth_;
        tokenImpl       = tokenImpl_;
        locker          = ISparkLocker(locker_);
        launchFeeWallet = launchFeeWallet_;
        launchFee       = launchFee_;

        dexes[initialFactory_] = DexConfig({
            positionManager: initialPositionMgr_,
            router:          initialRouter_,
            routerNoDeadline: initialRouterNoDeadline_,
            enabled:         true
        });
        emit DexAdded(initialFactory_, initialPositionMgr_, initialRouter_, initialRouterNoDeadline_);

        quoteTokens[weth_] = QuoteToken({
            marketCapRef: 5e18,
            wethPairFee:  0,
            enabled:      true
        });
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

    function setTokenImpl(address tokenImpl_) external onlyOwner {
        if (tokenImpl_ == address(0)) revert ZeroAddress();
        tokenImpl = tokenImpl_;
        emit TokenImplSet(tokenImpl_);
    }

    function _launchFeeRecipient() private view returns (address) {
        return launchFeeWallet == address(0) ? owner() : launchFeeWallet;
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

    function addDex(address factory_, address positionMgr_, address router_, bool routerNoDeadline_) external onlyOwner {
        if (factory_     == address(0)) revert ZeroAddress();
        if (positionMgr_ == address(0)) revert ZeroAddress();
        if (router_      == address(0)) revert ZeroAddress();
        dexes[factory_] = DexConfig({
            positionManager: positionMgr_,
            router:          router_,
            routerNoDeadline: routerNoDeadline_,
            enabled:         true
        });
        emit DexAdded(factory_, positionMgr_, router_, routerNoDeadline_);
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

    function launch(LaunchParams calldata p) external payable returns (address token, address pool, uint256 tokenId) {
        token = _deployAndInit(p.name, p.symbol, p.metaURI, p.vanitySalt);
        (pool, tokenId) = _setupAndRegister(token, p);
    }

    function _setupAndRegister(
        address token,
        LaunchParams calldata p
    ) private returns (address pool, uint256 tokenId) {
        if (!dexes[p.factory].enabled)          revert UnsupportedDex();
        if (!quoteTokens[p.quoteToken].enabled)  revert UnsupportedQuoteToken();
        if (msg.value < launchFee)               revert WrongFee();

        (bool feeOk,) = _launchFeeRecipient().call{value: launchFee}("");
        if (!feeOk) revert TransferFailed();
        uint256 extraEth = msg.value - launchFee;

        (address token0, address token1) = token < p.quoteToken
            ? (token,       p.quoteToken)
            : (p.quoteToken, token      );

        address existingPool = IUniswapV3Factory(p.factory).getPool(token0, token1, FEE_TIER);
        if (existingPool == address(0)) {
            pool = IUniswapV3Factory(p.factory).createPool(token0, token1, FEE_TIER);
        } else {
            (uint160 existingPrice,,,,,,) = IUniswapV3Pool(existingPool).slot0();
            if (existingPrice != 0) revert PoolAlreadyExists();
            pool = existingPool;
        }

        ISparkToken(token).setExempt(pool, true);

        IUniswapV3Pool(pool).initialize(
            _computeSqrtPriceX96(token, p.quoteToken, quoteTokens[p.quoteToken].marketCapRef)
        );

        tokenId = _mintAndRegister(
            dexes[p.factory].positionManager,
            token,
            p.feeWallet == address(0) ? msg.sender : p.feeWallet,
            token0, token1, pool
        );

        if (extraEth > 0) {
            DexConfig storage dex = dexes[p.factory];
            try this.instantBuy{value: extraEth}(
                p.quoteToken, token, extraEth, p.minQuoteOut, p.minTokensOut,
                dex.router, dex.routerNoDeadline, msg.sender
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

        emit TokenLaunched(
            token, msg.sender, p.factory, p.quoteToken,
            p.feeWallet == address(0) ? msg.sender : p.feeWallet,
            pool, tokenId
        );
    }

    receive() external payable {}

    function instantBuy(
        address quoteToken_,
        address token_,
        uint256 extraEth_,
        uint256 minQuoteOut_,
        uint256 minTokensOut_,
        address router_,
        bool    routerNoDeadline_,
        address recipient_
    ) external payable {
        if (msg.sender != address(this)) revert Unauthorized();

        uint256 quoteAmount;
        if (quoteToken_ == weth) {
            IWETHLocal(weth).deposit{value: extraEth_}();
            quoteAmount = extraEth_;
        } else {
            bool ok;
            (quoteAmount, ok) = _acquireQuoteToken(quoteToken_, extraEth_, minQuoteOut_, address(this));
            if (!ok) revert InstantBuyFailed();
        }

        _safeApprove(quoteToken_, router_, quoteAmount);
        uint256 tokensOut;
        if (routerNoDeadline_) {
            tokensOut = IV3SwapRouterNoDeadlineLocal(router_).exactInputSingle(IV3SwapRouterNoDeadlineLocal.ExactInputSingleParams({
                tokenIn:           quoteToken_,
                tokenOut:          token_,
                fee:               FEE_TIER,
                recipient:         recipient_,
                amountIn:          quoteAmount,
                amountOutMinimum:  minTokensOut_,
                sqrtPriceLimitX96: 0
            }));
        } else {
            tokensOut = ISwapRouterLocal(router_).exactInputSingle(ISwapRouterLocal.ExactInputSingleParams({
                tokenIn:           quoteToken_,
                tokenOut:          token_,
                fee:               FEE_TIER,
                recipient:         recipient_,
                deadline:          block.timestamp,
                amountIn:          quoteAmount,
                amountOutMinimum:  minTokensOut_,
                sqrtPriceLimitX96: 0
            }));
        }
        if (tokensOut < minTokensOut_) revert InstantBuyFailed();
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
        string calldata metaURI_,
        bytes32         vanitySalt_
    ) private returns (address token) {
        bytes32 salt = keccak256(abi.encode(msg.sender, vanitySalt_));
        token = _clone(tokenImpl, salt);
        if (uint16(uint160(token)) != VANITY_SUFFIX) revert VanityMismatch();
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

}
