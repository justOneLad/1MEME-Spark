// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// SparkCF — permissionless crowdfund launcher. A campaign targets a fixed
// USD goal (owner-configurable), TWAP-priced into native wei at creation.
// Contributions are native-only, over a fixed duration from an instant-live
// or scheduled start time. Goal is a soft floor, not a cap. A campaign that
// clears it deploys its token and pairs 100% of raised funds as liquidity —
// swapped into the creator's chosen DEX quote asset first if non-native —
// two-sided V3 (locker-registered) for tax-free tokens, or V2 with the LP
// burned for taxed tokens. Supply splits pro-rata between contributors and
// the LP; a campaign that misses its goal unlocks refunds instead.
//
// TWAP goal pricing averages up to two owner-configured sources: a
// stateless V3-style pool (observe()) and a V2-style pair, whose
// accumulator has no separate maintenance function — it advances as a side
// effect of normal createCampaign()/contribute() calls.
//
// Inherits SparkRouting for the DEX-quote-asset swap. Storage is
// append-only across upgrades.

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SparkRouting, Route} from "../common/SparkRouting.sol";
import {CFTwapMath} from "spark-cf-contracts/CFTwapMath.sol";

interface ISparkCFTokenLocal {
    function initSparkCF(
        string calldata name_, string calldata symbol_, string calldata metaURI_,
        uint16 taxBps_, address taxWallet_
    ) external;
    function setPair(address pair_) external;
    function renounceOwnership() external;
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ISparkLocker {
    function registerPosition(
        address token, uint256 tokenId, address feeWallet,
        address token0, address token1, address pool, address positionManager
    ) external;
}

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function slot0() external view returns (
        uint160 sqrtPriceX96, int24 tick, uint16 observationIndex,
        uint16  observationCardinality, uint16 observationCardinalityNext,
        uint32  feeProtocol, bool unlocked
    );
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0; address token1; uint24 fee;
        int24   tickLower; int24 tickUpper;
        uint256 amount0Desired; uint256 amount1Desired;
        uint256 amount0Min; uint256 amount1Min;
        address recipient; uint256 deadline;
    }
    function mint(MintParams calldata params)
        external payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IUniswapV2Router02Local {
    function factory() external view returns (address);
    function WETH() external view returns (address);
    function addLiquidity(
        address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired,
        uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    function addLiquidityETH(
        address token, uint256 amountTokenDesired, uint256 amountTokenMin,
        uint256 amountETHMin, address to, uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IUniswapV2FactoryLocal {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IWETHLocal {
    function deposit() external payable;
}

contract SparkCFLauncher is Initializable, UUPSUpgradeable, OwnableUpgradeable, SparkRouting {

    error ZeroAddress();
    error ZeroAmount();
    error CloneFailed();
    error VanityMismatch();
    error TaxTooHigh();
    error NotLiveYet();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error WrongFee();
    error CampaignNotFound();
    error AlreadyFinalized();
    error NotFinalized();
    error CampaignFailed_();
    error CampaignSucceeded_();
    error NothingToClaim();
    error PoolAlreadyExists();
    error InvalidBps();
    error NoTwapSourceConfigured();
    error V2OracleWarmingUp();
    error SwapFailed();

    uint16  public constant VANITY_SUFFIX = 0x1111;
    uint256 public constant TOTAL_SUPPLY  = 1_000_000_000e18;
    uint16  public constant MAX_TAX_BPS   = 500;
    uint24  private constant FEE_TIER     = 10_000;
    int24   private constant MIN_TICK     = -887_200;
    int24   private constant MAX_TICK     =  887_200;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    struct Campaign {
        address creator;
        string  name;
        string  symbol;
        string  metaURI;
        address dexQuoteAsset;      // address(0) = native, no swap needed at finalize
        uint256 goal;                // native wei, TWAP-computed at creation
        uint256 startTime;
        uint256 deadline;
        uint256 totalRaised;
        uint16  taxBps;
        address taxWallet;
        bytes32 vanitySalt;
        uint256 contributorBps;
        uint256 lpBps;
        bool    finalized;
        bool    succeeded;
        address token;
    }

    Campaign[] public campaigns;
    mapping(uint256 => mapping(address => uint256)) public contributed;

    address      public tokenImpl;
    ISparkLocker public locker;
    address      public weth;
    address      public v3Factory;
    address      public v3PositionManager;
    address      public v2Router;
    uint256      public contributorBps;
    uint256      public lpBps;
    uint256      public campaignFee;
    address      public feeWallet;

    uint256 public usdGoalTarget18;
    uint256 public campaignDuration;

    address public v3TwapPool;
    address public v3TwapStable;
    uint8   public v3TwapStableDecimals;
    uint32  public v3TwapWindow;

    address public v2TwapPair;
    address public v2TwapStable;
    uint8   public v2TwapStableDecimals;
    uint32  public v2TwapWindow;
    bool    public v2NativeIsToken0;
    uint256 public v2PriceCumulativeLast;
    uint32  public v2BlockTimestampLast;
    uint256 public v2PriceAverage;

    event CampaignCreated(uint256 indexed campaignId, address indexed creator, string name, string symbol, address dexQuoteAsset, uint256 goal, uint256 startTime, uint256 deadline, uint16 taxBps);
    event Contributed(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event CampaignSucceeded(uint256 indexed campaignId, address indexed token, uint256 totalRaised);
    event CampaignFailed(uint256 indexed campaignId, uint256 totalRaised, uint256 goal);
    event Claimed(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event Refunded(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event TokenImplSet(address indexed tokenImpl);
    event LockerSet(address indexed locker);
    event WethSet(address indexed weth);
    event V3FactorySet(address indexed factory);
    event V3PositionManagerSet(address indexed positionManager);
    event V2RouterSet(address indexed router);
    event FeeWalletSet(address indexed wallet);
    event CampaignFeeSet(uint256 fee);
    event SupplySplitSet(uint256 contributorBps, uint256 lpBps);
    event UsdGoalTargetSet(uint256 usdGoalTarget18);
    event CampaignDurationSet(uint256 duration);
    event V3TwapSourceSet(address indexed pool, address indexed stable, uint8 stableDecimals, uint32 window);
    event V2TwapSourceSet(address indexed pair, address indexed stable, uint8 stableDecimals, uint32 window);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address weth_,
        address tokenImpl_,
        address locker_,
        address v3Factory_,
        address v3PositionManager_,
        address v2Router_,
        address feeWallet_,
        uint256 campaignFee_
    ) external initializer {
        if (weth_               == address(0)) revert ZeroAddress();
        if (tokenImpl_          == address(0)) revert ZeroAddress();
        if (locker_             == address(0)) revert ZeroAddress();
        if (v3Factory_          == address(0)) revert ZeroAddress();
        if (v3PositionManager_  == address(0)) revert ZeroAddress();
        if (v2Router_           == address(0)) revert ZeroAddress();

        __Ownable_init(msg.sender);

        weth              = weth_;
        tokenImpl         = tokenImpl_;
        locker            = ISparkLocker(locker_);
        v3Factory         = v3Factory_;
        v3PositionManager = v3PositionManager_;
        v2Router          = v2Router_;
        feeWallet         = feeWallet_;
        campaignFee       = campaignFee_;

        contributorBps   = 8_000;
        lpBps             = 2_000;
        usdGoalTarget18   = 3_000e18;
        campaignDuration  = 2 hours;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _weth() internal view override returns (address) {
        return weth;
    }

    function setTokenImpl(address tokenImpl_) external onlyOwner {
        if (tokenImpl_ == address(0)) revert ZeroAddress();
        tokenImpl = tokenImpl_;
        emit TokenImplSet(tokenImpl_);
    }

    function setLocker(address locker_) external onlyOwner {
        if (locker_ == address(0)) revert ZeroAddress();
        locker = ISparkLocker(locker_);
        emit LockerSet(locker_);
    }

    function setWeth(address weth_) external onlyOwner {
        if (weth_ == address(0)) revert ZeroAddress();
        weth = weth_;
        emit WethSet(weth_);
    }

    function setV3Factory(address factory_) external onlyOwner {
        if (factory_ == address(0)) revert ZeroAddress();
        v3Factory = factory_;
        emit V3FactorySet(factory_);
    }

    function setV3PositionManager(address positionManager_) external onlyOwner {
        if (positionManager_ == address(0)) revert ZeroAddress();
        v3PositionManager = positionManager_;
        emit V3PositionManagerSet(positionManager_);
    }

    function setV2Router(address router_) external onlyOwner {
        if (router_ == address(0)) revert ZeroAddress();
        v2Router = router_;
        emit V2RouterSet(router_);
    }

    function setRoutes(address quoteToken_, Route[] calldata routes_) external onlyOwner {
        _setRoutes(quoteToken_, routes_);
    }

    function setFeeWallet(address wallet) external onlyOwner {
        feeWallet = wallet;
        emit FeeWalletSet(wallet);
    }

    function setCampaignFee(uint256 fee_) external onlyOwner {
        campaignFee = fee_;
        emit CampaignFeeSet(fee_);
    }

    function setSupplySplit(uint256 contributorBps_, uint256 lpBps_) external onlyOwner {
        if (contributorBps_ + lpBps_ != 10_000) revert InvalidBps();
        contributorBps = contributorBps_;
        lpBps          = lpBps_;
        emit SupplySplitSet(contributorBps_, lpBps_);
    }

    function setUsdGoalTarget(uint256 usdGoalTarget18_) external onlyOwner {
        if (usdGoalTarget18_ == 0) revert ZeroAmount();
        usdGoalTarget18 = usdGoalTarget18_;
        emit UsdGoalTargetSet(usdGoalTarget18_);
    }

    function setCampaignDuration(uint256 duration_) external onlyOwner {
        if (duration_ == 0) revert ZeroAmount();
        campaignDuration = duration_;
        emit CampaignDurationSet(duration_);
    }

    function setV3TwapSource(address pool_, address stable_, uint8 stableDecimals_, uint32 window_) external onlyOwner {
        v3TwapPool = pool_;
        v3TwapStable = stable_;
        v3TwapStableDecimals = stableDecimals_;
        v3TwapWindow = window_;
        emit V3TwapSourceSet(pool_, stable_, stableDecimals_, window_);
    }

    function setV2TwapSource(address pair_, address stable_, uint8 stableDecimals_, uint32 window_) external onlyOwner {
        v2TwapPair = pair_;
        v2TwapStable = stable_;
        v2TwapStableDecimals = stableDecimals_;
        v2TwapWindow = window_;
        v2NativeIsToken0 = weth < stable_;
        v2PriceCumulativeLast = 0;
        v2BlockTimestampLast = 0;
        v2PriceAverage = 0;
        emit V2TwapSourceSet(pair_, stable_, stableDecimals_, window_);
    }

    function _feeRecipient() private view returns (address) {
        return feeWallet == address(0) ? owner() : feeWallet;
    }

    function campaignCount() external view returns (uint256) {
        return campaigns.length;
    }

    function previewGoalNativeWei() external view returns (uint256) {
        return _computeGoalNativeWei();
    }

    function previewClaimable(uint256 campaignId_, address account) external view returns (uint256) {
        if (campaignId_ >= campaigns.length) revert CampaignNotFound();
        Campaign storage c = campaigns[campaignId_];
        if (!c.finalized || !c.succeeded) return 0;
        uint256 amount = contributed[campaignId_][account];
        if (amount == 0) return 0;
        uint256 contributorSupply = TOTAL_SUPPLY * c.contributorBps / 10_000;
        return contributorSupply * amount / c.totalRaised;
    }

    function createCampaign(
        string calldata name_,
        string calldata symbol_,
        string calldata metaURI_,
        address dexQuoteAsset_,
        uint256 startTime_,
        uint16  taxBps_,
        address taxWallet_,
        bytes32 vanitySalt_
    ) external payable returns (uint256 campaignId) {
        if (taxBps_ > MAX_TAX_BPS) revert TaxTooHigh();
        if (taxBps_ > 0 && taxWallet_ == address(0)) revert ZeroAddress();
        if (msg.value != campaignFee) revert WrongFee();

        _updateV2TwapIfDue();
        uint256 goal = _computeGoalNativeWei();

        if (campaignFee > 0) {
            (bool ok,) = _feeRecipient().call{value: campaignFee}("");
            if (!ok) revert TransferFailed();
        }

        uint256 startTime = startTime_ <= block.timestamp ? block.timestamp : startTime_;
        uint256 deadline = startTime + campaignDuration;

        campaignId = campaigns.length;
        campaigns.push(Campaign({
            creator:        msg.sender,
            name:           name_,
            symbol:         symbol_,
            metaURI:        metaURI_,
            dexQuoteAsset:  dexQuoteAsset_,
            goal:           goal,
            startTime:      startTime,
            deadline:       deadline,
            totalRaised:    0,
            taxBps:         taxBps_,
            taxWallet:      taxWallet_,
            vanitySalt:     vanitySalt_,
            contributorBps: contributorBps,
            lpBps:          lpBps,
            finalized:      false,
            succeeded:      false,
            token:          address(0)
        }));
        emit CampaignCreated(campaignId, msg.sender, name_, symbol_, dexQuoteAsset_, goal, startTime, deadline, taxBps_);
    }

    function contribute(uint256 campaignId_) external payable {
        if (campaignId_ >= campaigns.length) revert CampaignNotFound();
        Campaign storage c = campaigns[campaignId_];
        if (block.timestamp < c.startTime) revert NotLiveYet();
        if (block.timestamp >= c.deadline) revert DeadlinePassed();
        if (msg.value == 0) revert ZeroAmount();

        _updateV2TwapIfDue();

        contributed[campaignId_][msg.sender] += msg.value;
        c.totalRaised += msg.value;
        emit Contributed(campaignId_, msg.sender, msg.value);
    }

    function finalize(uint256 campaignId_) external returns (address token) {
        if (campaignId_ >= campaigns.length) revert CampaignNotFound();
        Campaign storage c = campaigns[campaignId_];
        if (block.timestamp < c.deadline) revert DeadlineNotPassed();
        if (c.finalized) revert AlreadyFinalized();

        c.finalized = true;

        if (c.totalRaised >= c.goal) {
            try this._deploySuccessToken(campaignId_) returns (address deployedToken) {
                c.succeeded = true;
                c.token = deployedToken;
                token = deployedToken;
                emit CampaignSucceeded(campaignId_, deployedToken, c.totalRaised);
            } catch {
                emit CampaignFailed(campaignId_, c.totalRaised, c.goal);
            }
        } else {
            emit CampaignFailed(campaignId_, c.totalRaised, c.goal);
        }
    }

    function _deploySuccessToken(uint256 campaignId_) external returns (address token) {
        if (msg.sender != address(this)) revert Unauthorized();
        Campaign storage c = campaigns[campaignId_];

        bytes32 salt = keccak256(abi.encode(c.creator, c.vanitySalt));
        token = _clone(tokenImpl, salt);
        if (uint16(uint160(token)) != VANITY_SUFFIX) revert VanityMismatch();

        uint256 contributorSupply = TOTAL_SUPPLY * c.contributorBps / 10_000;
        uint256 lpSupply = TOTAL_SUPPLY - contributorSupply;

        ISparkCFTokenLocal(token).initSparkCF(c.name, c.symbol, c.metaURI, c.taxBps, c.taxWallet);

        address quoteAsset = c.dexQuoteAsset;
        uint256 quoteAmount = c.totalRaised;
        if (quoteAsset != address(0)) {
            (uint256 out, bool ok) = _acquireQuoteToken(quoteAsset, c.totalRaised, 0, address(this));
            if (!ok) revert SwapFailed();
            quoteAmount = out;
        }

        if (c.taxBps == 0) {
            _seedV3(token, quoteAsset, lpSupply, quoteAmount, c.creator);
        } else {
            _seedV2Tax(token, quoteAsset, lpSupply, quoteAmount, c.creator);
        }

        ISparkCFTokenLocal(token).renounceOwnership();
    }

    function _seedV3(
        address token,
        address quoteCurrency,
        uint256 lpSupply,
        uint256 quoteAmount,
        address creator
    ) private {
        address quoteToken = quoteCurrency;
        if (quoteCurrency == address(0)) {
            IWETHLocal(weth).deposit{value: quoteAmount}();
            quoteToken = weth;
        }

        (address token0, address token1) = token < quoteToken ? (token, quoteToken) : (quoteToken, token);
        (uint256 amount0Desired, uint256 amount1Desired) = token == token0
            ? (lpSupply, quoteAmount)
            : (quoteAmount, lpSupply);

        address pool = IUniswapV3Factory(v3Factory).getPool(token0, token1, FEE_TIER);
        if (pool == address(0)) {
            pool = IUniswapV3Factory(v3Factory).createPool(token0, token1, FEE_TIER);
        } else {
            (uint160 existingPrice,,,,,,) = IUniswapV3Pool(pool).slot0();
            if (existingPrice != 0) revert PoolAlreadyExists();
        }

        IUniswapV3Pool(pool).initialize(_computeSqrtPriceX96(token, quoteToken, lpSupply, quoteAmount));

        _safeApprove(token, v3PositionManager, lpSupply);
        _safeApprove(quoteToken, v3PositionManager, quoteAmount);

        (uint256 tokenId,, uint256 amount0, uint256 amount1) = INonfungiblePositionManager(v3PositionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0:         token0,
                token1:         token1,
                fee:            FEE_TIER,
                tickLower:      MIN_TICK,
                tickUpper:      MAX_TICK,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min:     0,
                amount1Min:     0,
                recipient:      address(locker),
                deadline:       block.timestamp
            })
        );

        locker.registerPosition(token, tokenId, creator, token0, token1, pool, v3PositionManager);

        (uint256 tokenUsed, uint256 quoteUsed) = token == token0 ? (amount0, amount1) : (amount1, amount0);
        if (lpSupply > tokenUsed) _safeTransfer(token, creator, lpSupply - tokenUsed);
        if (quoteAmount > quoteUsed) _safeTransfer(quoteToken, creator, quoteAmount - quoteUsed);
    }

    function _seedV2Tax(
        address token,
        address quoteCurrency,
        uint256 lpSupply,
        uint256 quoteAmount,
        address creator
    ) private {
        address factory = IUniswapV2Router02Local(v2Router).factory();
        address quote = quoteCurrency == address(0) ? IUniswapV2Router02Local(v2Router).WETH() : quoteCurrency;
        if (IUniswapV2FactoryLocal(factory).getPair(token, quote) != address(0)) revert PoolAlreadyExists();

        _safeApprove(token, v2Router, lpSupply);
        uint256 tokenUsed;
        uint256 quoteUsed;
        if (quoteCurrency == address(0)) {
            (tokenUsed,quoteUsed,) = IUniswapV2Router02Local(v2Router).addLiquidityETH{value: quoteAmount}(
                token, lpSupply, 0, 0, DEAD, block.timestamp
            );
        } else {
            _safeApprove(quoteCurrency, v2Router, quoteAmount);
            (tokenUsed,quoteUsed,) = IUniswapV2Router02Local(v2Router).addLiquidity(
                token, quoteCurrency, lpSupply, quoteAmount, 0, 0, DEAD, block.timestamp
            );
        }

        address pair = IUniswapV2FactoryLocal(factory).getPair(token, quote);
        ISparkCFTokenLocal(token).setPair(pair);

        if (lpSupply > tokenUsed) _safeTransfer(token, creator, lpSupply - tokenUsed);

        if (quoteAmount > quoteUsed) {
            if (quoteCurrency == address(0)) {
                (bool ok,) = creator.call{value: quoteAmount - quoteUsed}("");
                if (!ok) revert TransferFailed();
            } else {
                _safeTransfer(quoteCurrency, creator, quoteAmount - quoteUsed);
            }
        }
    }

    function claim(uint256 campaignId_) external {
        if (campaignId_ >= campaigns.length) revert CampaignNotFound();
        Campaign storage c = campaigns[campaignId_];
        if (!c.finalized) revert NotFinalized();
        if (!c.succeeded) revert CampaignFailed_();
        uint256 amount = contributed[campaignId_][msg.sender];
        if (amount == 0) revert NothingToClaim();

        contributed[campaignId_][msg.sender] = 0;

        uint256 contributorSupply = TOTAL_SUPPLY * c.contributorBps / 10_000;
        uint256 share = contributorSupply * amount / c.totalRaised;

        ISparkCFTokenLocal(c.token).transfer(msg.sender, share);
        emit Claimed(campaignId_, msg.sender, share);
    }

    function claimRefund(uint256 campaignId_) external {
        if (campaignId_ >= campaigns.length) revert CampaignNotFound();
        Campaign storage c = campaigns[campaignId_];
        if (!c.finalized) revert NotFinalized();
        if (c.succeeded) revert CampaignSucceeded_();
        uint256 amount = contributed[campaignId_][msg.sender];
        if (amount == 0) revert NothingToClaim();

        contributed[campaignId_][msg.sender] = 0;

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Refunded(campaignId_, msg.sender, amount);
    }

    receive() external payable {}

    // ── TWAP goal pricing ────────────────────────────────────────────────────

    function _computeGoalNativeWei() private view returns (uint256) {
        bool v3Set = v3TwapPool != address(0);
        bool v2Set = v2TwapPair != address(0);
        if (!v3Set && !v2Set) revert NoTwapSourceConfigured();

        uint256 usdPerNative18;
        uint256 sources;

        if (v3Set) {
            usdPerNative18 += CFTwapMath.v3UsdPerNative18(v3TwapPool, v3TwapWindow, weth, v3TwapStable, v3TwapStableDecimals);
            sources++;
        }

        if (v2Set) {
            uint256 v2Price = CFTwapMath.v2UsdPerNative18(v2PriceAverage, v2TwapStableDecimals);
            if (v2Price == 0) {
                if (!v3Set) {
                    usdPerNative18 = CFTwapMath.v2SpotUsdPerNative18(v2TwapPair, v2NativeIsToken0, v2TwapStableDecimals);
                    sources = 1;
                }
            } else {
                usdPerNative18 += v2Price;
                sources++;
            }
        }

        if (sources == 0) revert V2OracleWarmingUp();
        usdPerNative18 = usdPerNative18 / sources;
        return usdGoalTarget18 * 1e18 / usdPerNative18;
    }

    function _updateV2TwapIfDue() private {
        if (v2TwapPair == address(0)) return;

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = CFTwapMath.v2CurrentCumulativePrices(v2TwapPair);
        uint256 priceCumulative = v2NativeIsToken0 ? price0Cumulative : price1Cumulative;

        if (v2BlockTimestampLast == 0) {
            v2PriceCumulativeLast = priceCumulative;
            v2BlockTimestampLast = blockTimestamp;
            return;
        }

        uint32 timeElapsed;
        unchecked { timeElapsed = blockTimestamp - v2BlockTimestampLast; }
        if (timeElapsed < v2TwapWindow) return;

        unchecked {
            v2PriceAverage = (priceCumulative - v2PriceCumulativeLast) / timeElapsed;
        }
        v2PriceCumulativeLast = priceCumulative;
        v2BlockTimestampLast = blockTimestamp;
    }

    // ── Shared helpers ───────────────────────────────────────────────────────

    function _clone(address impl, bytes32 salt) private returns (address instance) {
        assembly ("memory-safe") {
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

    function _computeSqrtPriceX96(address sparkToken, address quoteToken_, uint256 tokenAmount, uint256 quoteAmount)
        private pure returns (uint160)
    {
        if (sparkToken < quoteToken_) {
            return _sqrtPriceX96(tokenAmount, quoteAmount);
        } else {
            return _sqrtPriceX96(quoteAmount, tokenAmount);
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
}
