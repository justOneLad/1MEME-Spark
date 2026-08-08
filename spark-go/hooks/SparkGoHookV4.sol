// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// SparkGo's v4-style hook — anti-sandwich (same-block re-entry block), 2% sell fee.
// Non-upgradeable: redeployed fresh and repointed via addDex (CREATE2 address
// must match REQUIRED_PERMISSIONS).

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

interface IV4PoolManagerMinimal {
    function take(address currency, address to, uint256 amount) external;
}

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract SparkGoHookV4 {

    error ZeroAddress();
    error NotOwner();
    error NotLauncher();
    error NotPoolManager();
    error AlreadyRegistered();
    error NotRegistered();
    error SameBlockSwap();
    error TransferFailed();
    error InsufficientCTOFee();
    error NoCTOApplication();

    uint160 public constant REQUIRED_PERMISSIONS = 0xC4;

    uint256 public constant TOTAL_SUPPLY     = 1_000_000_000e18;
    uint256 public constant ANTIBOT_DURATION = 30 minutes;
    uint256 public constant HOOK_FEE_BPS     = 200;

    address public immutable poolManager;
    address public immutable launcher;
    address public owner;
    address public platformWallet;
    uint256 public platformBps = 3_000;

    struct PoolInfo {
        address token;
        address quoteCurrency;   // address(0) = native
        bool    tokenIsCurrency0;
        address creator;
        uint256 launchTimestamp;
        bool    registered;
    }

    mapping(bytes32 => PoolInfo)                   public pools;
    mapping(bytes32 => mapping(address => uint256)) private _lastSwapBlock;
    mapping(bytes32 => uint256)                     public  accruedFees;

    struct CTOApplication {
        address applicant;
        address newCreator;
        uint256 paid;
    }

    uint256 public ctoFee = 0.1 ether;
    address public ctoFeeWallet;
    mapping(bytes32 => CTOApplication) public ctoApplications;

    event PoolRegistered(bytes32 indexed poolId, address indexed token, address indexed creator);
    event FeesClaimed(bytes32 indexed poolId, uint256 amount);
    event PlatformWalletSet(address indexed wallet);
    event PlatformBpsSet(uint256 bps);
    event CTOFeeSet(uint256 fee);
    event CTOFeeWalletSet(address indexed wallet);
    event CTOApplied(bytes32 indexed poolId, address indexed applicant, address newCreator, uint256 paid);
    event CTOApproved(bytes32 indexed poolId, address newCreator);
    event CTORejected(bytes32 indexed poolId, address indexed applicant);

    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

    constructor(address poolManager_, address launcher_, address platformWallet_) {
        if (poolManager_    == address(0)) revert ZeroAddress();
        if (launcher_       == address(0)) revert ZeroAddress();
        if (platformWallet_ == address(0)) revert ZeroAddress();
        poolManager    = poolManager_;
        launcher       = launcher_;
        owner          = msg.sender;
        platformWallet = platformWallet_;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    function setPlatformWallet(address wallet) external onlyOwner {
        if (wallet == address(0)) revert ZeroAddress();
        platformWallet = wallet;
        emit PlatformWalletSet(wallet);
    }

    function setPlatformBps(uint256 bps) external onlyOwner {
        require(bps <= 10_000);
        platformBps = bps;
        emit PlatformBpsSet(bps);
    }

    function setCTOFee(uint256 fee_) external onlyOwner {
        ctoFee = fee_;
        emit CTOFeeSet(fee_);
    }

    function setCTOFeeWallet(address wallet_) external onlyOwner {
        ctoFeeWallet = wallet_;
        emit CTOFeeWalletSet(wallet_);
    }

    function _ctoFeeRecipient() private view returns (address) {
        return ctoFeeWallet == address(0) ? owner : ctoFeeWallet;
    }

    function applyForCTO(bytes32 poolId, address newCreator) external payable {
        if (!pools[poolId].registered) revert NotRegistered();
        if (newCreator == address(0)) revert ZeroAddress();
        if (msg.value < ctoFee) revert InsufficientCTOFee();
        ctoApplications[poolId] = CTOApplication({applicant: msg.sender, newCreator: newCreator, paid: msg.value});
        (bool ok,) = _ctoFeeRecipient().call{value: msg.value}("");
        if (!ok) revert TransferFailed();
        emit CTOApplied(poolId, msg.sender, newCreator, msg.value);
    }

    function approveCTO(bytes32 poolId) external onlyOwner {
        CTOApplication memory app = ctoApplications[poolId];
        if (app.newCreator == address(0)) revert NoCTOApplication();
        pools[poolId].creator = app.newCreator;
        delete ctoApplications[poolId];
        emit CTOApproved(poolId, app.newCreator);
    }

    function rejectCTO(bytes32 poolId) external onlyOwner {
        CTOApplication memory app = ctoApplications[poolId];
        if (app.newCreator == address(0)) revert NoCTOApplication();
        delete ctoApplications[poolId];
        emit CTORejected(poolId, app.applicant);
    }

    function registerPool(V4PoolKey calldata key, address token, address creator) external {
        if (msg.sender != launcher) revert NotLauncher();
        bytes32 poolId = keccak256(abi.encode(key));
        if (pools[poolId].registered) revert AlreadyRegistered();
        bool tokenIsCurrency0 = key.currency0 == token;
        pools[poolId] = PoolInfo({
            token:            token,
            quoteCurrency:    tokenIsCurrency0 ? key.currency1 : key.currency0,
            tokenIsCurrency0: tokenIsCurrency0,
            creator:          creator,
            launchTimestamp:  block.timestamp,
            registered:       true
        });
        emit PoolRegistered(poolId, token, creator);
    }

    function beforeInitialize(address, V4PoolKey calldata, uint160) external pure returns (bytes4) {
        return this.beforeInitialize.selector;
    }

    function afterInitialize(address, V4PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return this.afterInitialize.selector;
    }

    function beforeAddLiquidity(address, V4PoolKey calldata, bytes calldata, bytes calldata) external pure returns (bytes4) {
        return this.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(address, V4PoolKey calldata, bytes calldata, bytes calldata) external pure returns (bytes4) {
        return this.beforeRemoveLiquidity.selector;
    }

    function beforeDonate(address, V4PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.beforeDonate.selector;
    }

    function afterDonate(address, V4PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.afterDonate.selector;
    }

    function beforeSwap(address sender, V4PoolKey calldata key, V4SwapParams calldata, bytes calldata)
        external returns (bytes4, int256, uint24)
    {
        if (msg.sender != poolManager) revert NotPoolManager();
        bytes32 poolId = keccak256(abi.encode(key));
        PoolInfo storage info = pools[poolId];
        if (!info.registered) return (this.beforeSwap.selector, int256(0), 0);

        if (block.timestamp < info.launchTimestamp + ANTIBOT_DURATION) {
            if (_lastSwapBlock[poolId][sender] == block.number) revert SameBlockSwap();
            _lastSwapBlock[poolId][sender] = block.number;
        }

        return (this.beforeSwap.selector, int256(0), 0);
    }

    function afterSwap(address, V4PoolKey calldata key, V4SwapParams calldata params, int256 delta, bytes calldata)
        external returns (bytes4, int128)
    {
        if (msg.sender != poolManager) revert NotPoolManager();
        bytes32 poolId = keccak256(abi.encode(key));
        PoolInfo storage info = pools[poolId];
        if (!info.registered) return (this.afterSwap.selector, int128(0));

        int128 amount0Delta = int128(delta >> 128);
        int128 amount1Delta = int128(delta);
        (int128 tokenDelta, int128 quoteDelta) = info.tokenIsCurrency0
            ? (amount0Delta, amount1Delta)
            : (amount1Delta, amount0Delta);

        bool isExactInputSell = tokenDelta < 0 && params.amountSpecified < 0;
        if (!isExactInputSell || quoteDelta <= 0) return (this.afterSwap.selector, int128(0));

        uint256 feeCut = uint256(uint128(quoteDelta)) * HOOK_FEE_BPS / 10_000;
        if (feeCut == 0) return (this.afterSwap.selector, int128(0));

        accruedFees[poolId] += feeCut;
        IV4PoolManagerMinimal(msg.sender).take(info.quoteCurrency, address(this), feeCut);
        return (this.afterSwap.selector, int128(int256(feeCut)));
    }

    function claimFees(bytes32 poolId) external {
        PoolInfo storage info = pools[poolId];
        if (!info.registered) revert NotRegistered();

        uint256 amount = accruedFees[poolId];
        if (amount > 0) {
            accruedFees[poolId] = 0;
            uint256 platformCut = amount * platformBps / 10_000;
            uint256 creatorCut  = amount - platformCut;
            _pay(info.quoteCurrency, platformWallet, platformCut);
            _pay(info.quoteCurrency, info.creator, creatorCut);
        }
        emit FeesClaimed(poolId, amount);
    }

    receive() external payable {}

    function _pay(address currency, address to, uint256 amount) private {
        if (amount == 0) return;
        if (currency == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            if (!IERC20Minimal(currency).transfer(to, amount)) revert TransferFailed();
        }
    }
}
