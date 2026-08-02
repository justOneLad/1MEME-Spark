// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// One-time-use helper, not part of the ongoing system — same pattern as the
// original HookV4Factory.sol used for SparkHookV4 (see Deployment.md's
// "Deprecated / abandoned" entry on the first SparkHookV4 attempt for why
// this exists): a plain EOA can't execute the CREATE2 opcode directly, so
// Foundry routes a salted `new X{salt}()` broadcast from an EOA through the
// canonical CREATE2 deployer proxy (0x4e59b44847b379578588920cA78FbF26c0B4956C).
// That makes the proxy `msg.sender` inside the hook's constructor, permanently
// locking `owner` to an address that can never call anything back. Deploying
// via this factory instead makes the factory `msg.sender` at construction
// time, then this contract calls `transferOwnership` back to the real
// deployer atomically in the same transaction.

import {SparkGoHookV4} from "spark-go-contracts/hooks/SparkGoHookV4.sol";

contract SparkGoHookFactory {
    function deploy(bytes32 salt, address poolManager_, address launcher_, address platformWallet_, address newOwner_)
        external returns (address hook)
    {
        hook = address(new SparkGoHookV4{salt: salt}(poolManager_, launcher_, platformWallet_));
        SparkGoHookV4(payable(hook)).transferOwnership(newOwner_);
    }
}
