// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// Shared base for tests that need real BSC mainnet state.

import {Test} from "forge-std/Test.sol";

abstract contract Fork is Test {
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    address constant PANCAKE_V3_FACTORY          = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address constant PANCAKE_V3_POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address constant PANCAKE_V3_SMART_ROUTER     = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;

    address constant UNISWAP_V3_FACTORY          = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
    address constant UNISWAP_V3_POSITION_MANAGER = 0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613;
    address constant UNISWAP_V3_SWAP_ROUTER02    = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;

    address constant UNISWAP_V2_ROUTER  = 0x8547e2E16783Fdc559C435fDc158d572D1bD0970;
    address constant PANCAKE_V2_ROUTER  = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    address constant UNISWAP_V4_POSITION_MANAGER = 0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b;
    address constant UNISWAP_V4_POOL_MANAGER     = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant UNISWAP_V4_PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant PANCAKE_INF_POSITION_MANAGER = 0x55f4c8abA71A1e923edC303eb4fEfF14608cC226;
    address constant PANCAKE_INF_VAULT             = 0x238a358808379702088667322f80aC48bAd5e6c4;
    address constant PANCAKE_INF_CL_POOL_MANAGER   = 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b;
    address constant PANCAKE_INF_PERMIT2           = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;

    address constant NVDA = 0xA9eE28C80f960B889dFbd1902055218cBa016F75;
    uint24  constant NVDA_USDT_FEE = 10_000;

    address constant SPCX = 0xd0a58BC9D88D3FF48C0294Cb7e45937d0E41A928;
    uint24  constant SPCX_USDT_FEE = 10_000;

    address constant DEPLOYER = address(0xD100);

    function setUp() public virtual {
        string memory rpc = vm.envOr("BSC_RPC_URL", string("https://bsc-dataseed.binance.org"));
        vm.createSelectFork(rpc);
        vm.deal(DEPLOYER, 100 ether);
    }
}
