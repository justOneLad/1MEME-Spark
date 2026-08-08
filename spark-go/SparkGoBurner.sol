// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// SparkGo's burn-and-reward utility. Currency-general: tracks and swaps
// whichever currency a given pool actually uses, not just native BNB.

import "../common/SparkRouting.sol";

interface ISparkHookV4 {
    function claimFees(bytes32 poolId) external;
}

interface ISparkHookInfinity {
    function claimFees(bytes32 poolId) external;
}

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract SparkGoBurner is SparkRouting {

    error NothingToBurn();
    error TransferFailed_();

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant CALLER_BPS = 500;

    uint24  private constant HOOK_FEE             = 0;
    int24   private constant TICK_SPACING         = 200;
    uint16  private constant INFINITY_HOOK_BITMAP = 0x8C0;

    event Burned(address indexed token, address indexed quoteCurrency, address indexed caller, uint256 quoteIn, uint256 callerReward, uint256 tokenBurned);

    receive() external payable {}

    function _weth() internal pure override returns (address) {
        return address(0); // unused, no leg-1 fallback routing here
    }

    function burnV4(address poolManager_, address hook_, address token, address quoteToken_)
        external returns (uint256 tokenBurned, uint256 callerReward)
    {
        bytes32 poolId = _v4PoolId(hook_, token, quoteToken_);
        uint256 balBefore = _balanceOf(quoteToken_, address(this));
        ISparkHookV4(hook_).claimFees(poolId);
        uint256 quoteIn = _balanceOf(quoteToken_, address(this)) - balBefore;
        if (quoteIn == 0) revert NothingToBurn();

        callerReward = quoteIn * CALLER_BPS / 10_000;
        uint256 swapAmount = quoteIn - callerReward;

        tokenBurned = _executeV4Swap(poolManager_, hook_, HOOK_FEE, TICK_SPACING, quoteToken_, token, swapAmount, 0, address(this));
        if (tokenBurned > 0) IERC20Minimal(token).transfer(DEAD, tokenBurned);
        if (callerReward > 0) _payCaller(quoteToken_, callerReward);

        emit Burned(token, quoteToken_, msg.sender, quoteIn, callerReward, tokenBurned);
    }

    function burnInfinity(address vault_, address clPoolManager_, address hook_, address token, address quoteToken_)
        external returns (uint256 tokenBurned, uint256 callerReward)
    {
        bytes32 poolId = _infinityPoolId(clPoolManager_, hook_, token, quoteToken_);
        uint256 balBefore = _balanceOf(quoteToken_, address(this));
        ISparkHookInfinity(hook_).claimFees(poolId);
        uint256 quoteIn = _balanceOf(quoteToken_, address(this)) - balBefore;
        if (quoteIn == 0) revert NothingToBurn();

        callerReward = quoteIn * CALLER_BPS / 10_000;
        uint256 swapAmount = quoteIn - callerReward;

        tokenBurned = _executeInfinitySwap(vault_, clPoolManager_, hook_, HOOK_FEE, _infinityParameters(), quoteToken_, token, swapAmount, 0, address(this));
        if (tokenBurned > 0) IERC20Minimal(token).transfer(DEAD, tokenBurned);
        if (callerReward > 0) _payCaller(quoteToken_, callerReward);

        emit Burned(token, quoteToken_, msg.sender, quoteIn, callerReward, tokenBurned);
    }

    function _v4PoolId(address hook_, address token, address quoteToken_) private pure returns (bytes32) {
        (address c0, address c1) = token < quoteToken_ ? (token, quoteToken_) : (quoteToken_, token);
        V4PoolKey memory key = V4PoolKey({
            currency0:   c0,
            currency1:   c1,
            fee:         HOOK_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook_
        });
        return keccak256(abi.encode(key));
    }

    function _infinityPoolId(address clPoolManager_, address hook_, address token, address quoteToken_) private pure returns (bytes32) {
        (address c0, address c1) = token < quoteToken_ ? (token, quoteToken_) : (quoteToken_, token);
        InfinityPoolKey memory key = InfinityPoolKey({
            currency0:   c0,
            currency1:   c1,
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

    function _balanceOf(address currency, address account) private view returns (uint256) {
        if (currency == address(0)) return account.balance;
        return IERC20Minimal(currency).balanceOf(account);
    }

    function _payCaller(address currency, uint256 amount) private {
        if (currency == address(0)) {
            (bool ok,) = msg.sender.call{value: amount}("");
            if (!ok) revert TransferFailed_();
        } else {
            if (!IERC20Minimal(currency).transfer(msg.sender, amount)) revert TransferFailed_();
        }
    }
}
