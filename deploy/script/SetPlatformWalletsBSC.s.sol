// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Owner-only config update on BSC: repoints every platform/CTO/campaign fee
// wallet (SparkLocker x2, SparkGoHookV4, SparkGoHookInfinity,
// MerkleDistributor) to the new multisig. launchFeeWallet on both launchers
// is untouched — it stays separate from the rest of the platform's fee flow.

import {Script} from "forge-std/Script.sol";

interface IFeeWalletSettable {
    function setPlatformWallet(address wallet) external;
    function setCTOFeeWallet(address wallet_) external;
}

interface IMerkleDistributorFeeWallet {
    function setFeeWallet(address wallet_) external;
}

contract SetPlatformWalletsBSC is Script {
    address constant MULTISIG = 0x56e6A19fF30bB4d91926e4Acf03E1CFaB2cE36d0;

    address constant LOCKER_V1 = 0xA69B4B4003483E7Ca27DDf1bE8cBC7e723afcF86;
    address constant LOCKER_GO = 0x01245e814bbc3A1DC3b24924FB0E4E3b6863105B;
    address constant HOOK_V4        = 0x5bA7D23C085418fd44B971726e60d4864c8400c4;
    address constant HOOK_INFINITY  = 0x05AAb89F069DFAe5723DaF7c8dC21995f37729Dc;
    address constant MERKLE_DISTRIBUTOR = 0x20ED1b487dd2A172D5ba0ED33562370142Cc338b;

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

        IFeeWalletSettable(HOOK_INFINITY).setPlatformWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);
        IFeeWalletSettable(HOOK_INFINITY).setCTOFeeWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);

        IMerkleDistributorFeeWallet(MERKLE_DISTRIBUTOR).setFeeWallet(MULTISIG);
        vm.sleep(TX_DELAY_MS);

        vm.stopBroadcast();
    }
}
