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

interface ISparkHookV4 {
    function claimFees(bytes32 poolId) external;
}

interface ISparkHookInfinity {
    function claimFees(bytes32 poolId) external;
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

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract SparkBurner {

    error NothingToBurn();
    error Unauthorized();
    error TransferFailed();

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant CALLER_BPS = 500;

    uint24  private constant HOOK_FEE             = 0;
    int24   private constant TICK_SPACING         = 200;
    uint16  private constant INFINITY_HOOK_BITMAP = 0x8C0;
    uint160 private constant MIN_SQRT_PRICE       = 4295128739;

    address private _cbExpected;

    event Burned(address indexed token, address indexed caller, uint256 nativeIn, uint256 callerReward, uint256 tokenBurned);

    receive() external payable {}

    function burnV4(address poolManager_, address hook_, address token) external returns (uint256 tokenBurned, uint256 callerReward) {
        bytes32 poolId = _v4PoolId(hook_, token);
        uint256 balBefore = address(this).balance;
        ISparkHookV4(hook_).claimFees(poolId);
        uint256 nativeIn = address(this).balance - balBefore;
        if (nativeIn == 0) revert NothingToBurn();

        callerReward = nativeIn * CALLER_BPS / 10_000;
        uint256 swapAmount = nativeIn - callerReward;

        _cbExpected = poolManager_;
        bytes memory result = IV4PoolManager(poolManager_).unlock(abi.encode(hook_, token, swapAmount));
        _cbExpected = address(0);
        tokenBurned = abi.decode(result, (uint256));

        if (tokenBurned > 0) IERC20Minimal(token).transfer(DEAD, tokenBurned);

        if (callerReward > 0) {
            (bool ok,) = msg.sender.call{value: callerReward}("");
            if (!ok) revert TransferFailed();
        }

        emit Burned(token, msg.sender, nativeIn, callerReward, tokenBurned);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (_cbExpected == address(0) || msg.sender != _cbExpected) revert Unauthorized();
        (address hook_, address token, uint256 swapAmount) = abi.decode(data, (address, address, uint256));

        V4PoolKey memory key = V4PoolKey({
            currency0:   address(0),
            currency1:   token,
            fee:         HOOK_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook_
        });
        int256 delta = IV4PoolManager(msg.sender).swap(
            key,
            V4SwapParams({zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: MIN_SQRT_PRICE + 1}),
            ""
        );
        uint256 amountOut = uint256(uint128(int128(delta)));

        IV4PoolManager(msg.sender).settle{value: swapAmount}();
        IV4PoolManager(msg.sender).take(token, address(this), amountOut);
        return abi.encode(amountOut);
    }

    function burnInfinity(address vault_, address clPoolManager_, address hook_, address token) external returns (uint256 tokenBurned, uint256 callerReward) {
        bytes32 poolId = _infinityPoolId(clPoolManager_, hook_, token);
        uint256 balBefore = address(this).balance;
        ISparkHookInfinity(hook_).claimFees(poolId);
        uint256 nativeIn = address(this).balance - balBefore;
        if (nativeIn == 0) revert NothingToBurn();

        callerReward = nativeIn * CALLER_BPS / 10_000;
        uint256 swapAmount = nativeIn - callerReward;

        _cbExpected = vault_;
        bytes memory result = IVault(vault_).lock(abi.encode(clPoolManager_, hook_, token, swapAmount));
        _cbExpected = address(0);
        tokenBurned = abi.decode(result, (uint256));

        if (tokenBurned > 0) IERC20Minimal(token).transfer(DEAD, tokenBurned);

        if (callerReward > 0) {
            (bool ok,) = msg.sender.call{value: callerReward}("");
            if (!ok) revert TransferFailed();
        }

        emit Burned(token, msg.sender, nativeIn, callerReward, tokenBurned);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        if (_cbExpected == address(0) || msg.sender != _cbExpected) revert Unauthorized();
        (address clPoolManager_, address hook_, address token, uint256 swapAmount) =
            abi.decode(data, (address, address, address, uint256));

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
            InfinitySwapParams({zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: MIN_SQRT_PRICE + 1}),
            ""
        );
        uint256 amountOut = uint256(uint128(int128(delta)));

        IVault(msg.sender).settle{value: swapAmount}();
        IVault(msg.sender).take(token, address(this), amountOut);
        return abi.encode(amountOut);
    }

    function _v4PoolId(address hook_, address token) private pure returns (bytes32) {
        V4PoolKey memory key = V4PoolKey({
            currency0:   address(0),
            currency1:   token,
            fee:         HOOK_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook_
        });
        return keccak256(abi.encode(key));
    }

    function _infinityPoolId(address clPoolManager_, address hook_, address token) private pure returns (bytes32) {
        InfinityPoolKey memory key = InfinityPoolKey({
            currency0:   address(0),
            currency1:   token,
            hooks:       hook_,
            poolManager: clPoolManager_,
            fee:         HOOK_FEE,
            parameters:  _infinityParameters()
        });
        return keccak256(abi.encode(key));
    }

    function _infinityParameters() private pure returns (bytes32) {
        return bytes32((uint256(uint24(TICK_SPACING)) << 16) | INFINITY_HOOK_BITMAP);
    }
}
