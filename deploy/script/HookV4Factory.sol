// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme

import {SparkHookV4} from "spark-v2-contracts/hooks/SparkHookV4.sol";

contract HookV4Factory {
    function deploy(
        bytes32 salt,
        address poolManager_,
        address launcher_,
        address platformWallet_,
        address newOwner_
    ) external returns (address hook) {
        hook = address(new SparkHookV4{salt: salt}(poolManager_, launcher_, platformWallet_));
        SparkHookV4(payable(hook)).transferOwnership(newOwner_);
    }
}
