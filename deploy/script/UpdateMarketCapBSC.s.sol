// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Owner-only config update on BSC: drops every quote token's marketCapRef on
// SparkLauncher/SparkGo, and SparkCF's usdGoalTarget18, from ~$2,000/$3,000
// to a $1,000 reference. Each marketCapRef below was computed from a live
// on-chain price read (PancakeSwap V3 pools for WBNB/AAPLB/NVDAB/TSLAB/SPCXB
// against USDT, PancakeSwap V2 reserves for 1COIN against WBNB) at broadcast
// time, not a stale/assumed figure.

import {Script, console2} from "forge-std/Script.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {SparkCFLauncher} from "spark-cf-contracts/SparkCFLauncher.sol";

contract UpdateMarketCapBSC is Script {
    address constant SPARK_LAUNCHER_PROXY = 0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973;
    address constant SPARKGO_PROXY        = 0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C;
    address constant SPARKCF_PROXY        = 0xCe53c97A672B10031af9864f7960656124AC7a95;

    address constant WBNB    = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT    = 0x55d398326f99059fF775485246999027B3197955;
    address constant USDC    = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address constant USD1    = 0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d;
    address constant AAPLB   = 0x431a3BEE82E2ca41e49895CbECE5bB0F76A89b7A;
    address constant NVDAB   = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;
    address constant TSLAB   = 0x5b1910eAaD6450E50f816082Aa078C41F10C292f;
    address constant SPCXB   = 0xbe9D156892E55e7154BcD3cB0FEA677F9D3103E1;
    address constant ONECOIN = 0xe43eF1fE041Ba9E8da87E8C5bFD583B3b46A1111;

    uint256 constant WBNB_REF_1000USD    = 1430517866785047552;   // ~1.431 BNB @ $699.05
    uint256 constant AAPLB_REF_1000USD   = 3183502267587283968;   // ~3.184 AAPLB @ $314.12
    uint256 constant NVDAB_REF_1000USD   = 4835644393511081984;   // ~4.836 NVDAB @ $206.80
    uint256 constant TSLAB_REF_1000USD   = 2889424801684345856;   // ~2.889 TSLAB @ $346.09
    uint256 constant SPCXB_REF_1000USD   = 7190916773047241728;   // ~7.191 SPCXB @ $139.06
    uint256 constant ONECOIN_REF_1000USD = 49586625774437992;     // ~0.0496 1COIN @ $20,166.73
    uint256 constant STABLE_REF_1000USD  = 1000e18;               // USDT/USDC/USD1, 18-decimal $1 pegs

    uint256 constant TX_DELAY_MS = 10000;

    function run() external {
        vm.startBroadcast();

        SparkLauncher launcher = SparkLauncher(payable(SPARK_LAUNCHER_PROXY));
        SparkGoLauncher goLauncher = SparkGoLauncher(payable(SPARKGO_PROXY));
        SparkCFLauncher cfLauncher = SparkCFLauncher(payable(SPARKCF_PROXY));

        launcher.setMarketCapRef(WBNB, WBNB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(USDT, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(USDC, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(USD1, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(AAPLB, AAPLB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(NVDAB, NVDAB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(TSLAB, TSLAB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(SPCXB, SPCXB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        launcher.setMarketCapRef(ONECOIN, ONECOIN_REF_1000USD);
        vm.sleep(TX_DELAY_MS);

        goLauncher.setMarketCapRef(address(0), WBNB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(USDT, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(USDC, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(USD1, STABLE_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(AAPLB, AAPLB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(NVDAB, NVDAB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(TSLAB, TSLAB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(SPCXB, SPCXB_REF_1000USD);
        vm.sleep(TX_DELAY_MS);
        goLauncher.setMarketCapRef(ONECOIN, ONECOIN_REF_1000USD);
        vm.sleep(TX_DELAY_MS);

        cfLauncher.setUsdGoalTarget(1000e18);
        vm.sleep(TX_DELAY_MS);

        vm.stopBroadcast();
    }
}
