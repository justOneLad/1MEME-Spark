// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme

import {Script, console2} from "forge-std/Script.sol";
import {SparkToken} from "spark-contracts/SparkToken.sol";
import {SparkLocker} from "spark-contracts/SparkLocker.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncher.sol";

contract DeploySparkV1 is Script {
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // PancakeSwap V3 — registered as the initial DEX. Its SmartRouter/SwapRouter keep the
    // original ISwapRouter shape (ExactInput*Params includes `deadline`).
    address constant PANCAKE_V3_FACTORY          = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address constant PANCAKE_V3_POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address constant PANCAKE_V3_SMART_ROUTER     = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;

    // Uniswap V3 — registered as a second DEX via addDex(). SwapRouter02 dropped `deadline`
    // from ExactInput*Params, so it's flagged routerNoDeadline = true.
    address constant UNISWAP_V3_FACTORY          = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
    address constant UNISWAP_V3_POSITION_MANAGER = 0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613;
    address constant UNISWAP_V3_SWAP_ROUTER02    = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;

    // Quote tokens (18 decimals each, confirmed on-chain). wethPairFee is the fee tier of each
    // token's deepest existing WBNB pool on PancakeSwap V3, used to build the multihop instant-buy
    // path (weth -> quoteToken -> sparkToken). marketCapRef targets ~$3,000 initial market cap.
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    uint24  constant USDT_WBNB_FEE = 500;   // 0.05% — deepest USDT/WBNB pool (~$56M TVL)

    address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    uint24  constant USDC_WBNB_FEE = 100;   // 0.01% — deepest USDC/WBNB pool (~$4.3M TVL)

    address constant USD1 = 0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d;
    uint24  constant USD1_WBNB_FEE = 100;   // 0.01% — deepest USD1/WBNB pool (~$3.7M TVL)

    uint256 constant STABLE_MARKET_CAP_REF = 3_000e18; // ~$3,000 initial market cap

    uint256 constant LAUNCH_FEE = 0.001111 ether;

    function run() external returns (
        address tokenImpl,
        address locker,
        address launcher
    ) {
        vm.startBroadcast();
        address deployer = msg.sender;

        tokenImpl = address(new SparkToken());
        console2.log("SparkToken impl :", tokenImpl);

        locker = address(new SparkLocker(deployer));
        console2.log("SparkLocker     :", locker);

        launcher = address(new SparkLauncher(
            WBNB,
            tokenImpl,
            locker,
            address(0), // launchFeeWallet_ = address(0) -> defaults to owner (deployer)
            PANCAKE_V3_FACTORY,
            PANCAKE_V3_POSITION_MANAGER,
            PANCAKE_V3_SMART_ROUTER,
            false,      // PancakeSwap router keeps the `deadline` field
            LAUNCH_FEE
        ));
        console2.log("SparkLauncher   :", launcher);

        SparkLocker(locker).setLauncher(launcher);

        SparkLauncher(payable(launcher)).addDex(
            UNISWAP_V3_FACTORY,
            UNISWAP_V3_POSITION_MANAGER,
            UNISWAP_V3_SWAP_ROUTER02,
            true        // SwapRouter02 dropped the `deadline` field
        );

        SparkLauncher(payable(launcher)).addQuoteToken(USDT, STABLE_MARKET_CAP_REF, USDT_WBNB_FEE);
        SparkLauncher(payable(launcher)).addQuoteToken(USDC, STABLE_MARKET_CAP_REF, USDC_WBNB_FEE);
        SparkLauncher(payable(launcher)).addQuoteToken(USD1, STABLE_MARKET_CAP_REF, USD1_WBNB_FEE);

        vm.stopBroadcast();
    }
}
