// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Owner-only config update on Ethereum: repoints every platform/CTO/campaign
// fee wallet (SparkLocker x2, SparkGoHookV4, MerkleDistributor) to the new
// multisig. No PancakeSwap Infinity hook on Ethereum. launchFeeWallet on
// both launchers is untouched — it stays separate from the rest of the
// platform's fee flow.

import {Script} from "forge-std/Script.sol";

interface IFeeWalletSettable {
    function setPlatformWallet(address wallet) external;
    function setCTOFeeWallet(address wallet_) external;
}

interface IMerkleDistributorFeeWallet {
    function setFeeWallet(address wallet_) external;
}

contract SetPlatformWalletsEthereum is Script {
    address constant MULTISIG = 0x56e6A19fF30bB4d91926e4Acf03E1CFaB2cE36d0;

    address constant LOCKER_V1 = 0x2C238982945d5bE37dc6cFDFDD0c942458326C32;
    address constant LOCKER_GO = 0x541b04c5389E540bcc875EA14F699E539f96F76A;
    address constant HOOK_V4   = 0x331CC61E71249Ba26E591A2b2ee563F588d980C4;
    address constant MERKLE_DISTRIBUTOR = 0xcB3ccF9f74c08A70b2B1bf7c111391d158D18B1c;

    uint256 constant TX_DELAY_MS = 10000;

    function run() external {
        vm.startBroadcast();

        IFeeWalletSettable(LOCKER_V1).setPlatformWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);
        IFeeWalletSettable(LOCKER_V1).setCTOFeeWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);

        IFeeWalletSettable(LOCKER_GO).setPlatformWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);
        IFeeWalletSettable(LOCKER_GO).setCTOFeeWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);

        IFeeWalletSettable(HOOK_V4).setPlatformWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);
        IFeeWalletSettable(HOOK_V4).setCTOFeeWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);

        IMerkleDistributorFeeWallet(MERKLE_DISTRIBUTOR).setFeeWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);

        vm.stopBroadcast();
    }
}
