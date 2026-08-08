// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// One-time-use deploy helper. A salted `new X{salt}()` broadcast from an EOA
// routes through the canonical CREATE2 deployer proxy
// (0x4e59b44847b379578588920cA78FbF26c0B4956C), which would permanently lock
// the hook's `owner` to that proxy. Deploying through this factory instead
// makes the factory `msg.sender` at construction, then it transfers
// ownership back to the real deployer atomically in the same transaction.

import {SparkGoHookV4} from "spark-go-contracts/hooks/SparkGoHookV4.sol";

contract SparkGoHookFactory {
    function deploy(bytes32 salt, address poolManager_, address launcher_, address platformWallet_, address newOwner_)
        external returns (address hook)
    {
        hook = address(new SparkGoHookV4{salt: salt}(poolManager_, launcher_, platformWallet_));
        SparkGoHookV4(payable(hook)).transferOwnership(newOwner_);
    }
}
