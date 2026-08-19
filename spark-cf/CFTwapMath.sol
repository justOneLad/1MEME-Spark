// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// TWAP price math for SparkCFLauncher, split into an externally-linked
// library to keep the launcher's bytecode under the EIP-170 size limit.
// Stateless — SparkCFLauncher owns the TWAP accumulator storage and passes
// values in as plain parameters.

import {TickMath} from "spark-cf-contracts/TickMath.sol";
import {FullMath} from "spark-cf-contracts/FullMath.sol";

interface IUniswapV3PoolTwap {
    function observe(uint32[] calldata secondsAgos)
        external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}

interface IUniswapV2PairTwap {
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

library CFTwapMath {
    function tickToUsdPerNative18(int24 tick, address native_, address stable_, uint8 stableDecimals_)
        public pure returns (uint256)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 stableWeiPerNativeToken;
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            stableWeiPerNativeToken = native_ < stable_
                ? FullMath.mulDiv(ratioX192, 1e18, 1 << 192)
                : FullMath.mulDiv(1 << 192, 1e18, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            stableWeiPerNativeToken = native_ < stable_
                ? FullMath.mulDiv(ratioX128, 1e18, 1 << 128)
                : FullMath.mulDiv(1 << 128, 1e18, ratioX128);
        }
        return stableWeiPerNativeToken * (10 ** (18 - stableDecimals_));
    }

    function v3UsdPerNative18(address pool, uint32 window, address native_, address stable_, uint8 stableDecimals_)
        public view returns (uint256)
    {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = window;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives,) = IUniswapV3PoolTwap(pool).observe(secondsAgos);
        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        int24 avgTick = int24(delta / int56(uint56(window)));
        if (delta < 0 && (delta % int56(uint56(window)) != 0)) avgTick--;
        return tickToUsdPerNative18(avgTick, native_, stable_, stableDecimals_);
    }

    function v2CurrentCumulativePrices(address pair)
        public view returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        blockTimestamp = uint32(block.timestamp);
        price0Cumulative = IUniswapV2PairTwap(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2PairTwap(pair).price1CumulativeLast();
        (uint112 reserve0, uint112 reserve1, uint32 timestampLast) = IUniswapV2PairTwap(pair).getReserves();
        if (timestampLast != blockTimestamp) {
            uint32 timeElapsed;
            unchecked { timeElapsed = blockTimestamp - timestampLast; }
            unchecked {
                price0Cumulative += ((uint256(reserve1) << 112) / uint256(reserve0)) * timeElapsed;
                price1Cumulative += ((uint256(reserve0) << 112) / uint256(reserve1)) * timeElapsed;
            }
        }
    }

    function v2UsdPerNative18(uint256 priceAverage, uint8 stableDecimals_) public pure returns (uint256) {
        if (priceAverage == 0) return 0;
        uint256 stableWeiPerNativeToken = FullMath.mulDiv(priceAverage, 1e18, 1 << 112);
        return stableWeiPerNativeToken * (10 ** (18 - stableDecimals_));
    }

    function v2SpotUsdPerNative18(address pair, bool nativeIsToken0, uint8 stableDecimals_)
        public view returns (uint256)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairTwap(pair).getReserves();
        (uint256 nativeReserve, uint256 stableReserve) = nativeIsToken0
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));
        uint256 stableWeiPerNativeToken = FullMath.mulDiv(stableReserve, 1e18, nativeReserve);
        return stableWeiPerNativeToken * (10 ** (18 - stableDecimals_));
    }
}
