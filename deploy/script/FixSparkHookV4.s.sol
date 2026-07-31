// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme

import {Script, console2} from "forge-std/Script.sol";
import {SparkLauncherV2} from "spark-v2-contracts/SparkLauncherV2.sol";
import {SparkHookV4} from "spark-v2-contracts/hooks/SparkHookV4.sol";
import {HookV4Factory} from "./HookV4Factory.sol";

contract FixSparkHookV4 is Script {
    address constant LAUNCHER = 0xcD5B9F286cd5A2cE2fBe160bAfc018a1159d5c77;
    address constant V4_POSITION_MANAGER = 0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b;
    address constant V4_POOL_MANAGER     = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant V4_PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external returns (address factory, address hookV4) {
        vm.startBroadcast();
        address deployer = msg.sender;

        SparkLauncherV2 launcher = SparkLauncherV2(payable(LAUNCHER));
        require(launcher.owner() == deployer, "not the owner of this launcher");

        factory = address(new HookV4Factory());
        console2.log("HookV4Factory      :", factory);

        bytes memory hookV4Code = abi.encodePacked(
            type(SparkHookV4).creationCode,
            abi.encode(V4_POOL_MANAGER, LAUNCHER, deployer)
        );
        bytes32 hookV4InitCodeHash = keccak256(hookV4Code);
        bytes32 salt = _mineHookSalt(hookV4InitCodeHash, 0xC4, factory);

        hookV4 = HookV4Factory(factory).deploy(salt, V4_POOL_MANAGER, LAUNCHER, deployer, deployer);
        require(uint160(hookV4) & 0x3FFF == 0xC4, "hookV4 permission bits mismatch");
        require(SparkHookV4(payable(hookV4)).owner() == deployer, "hookV4 owner fixup failed");
        console2.log("SparkHookV4 (fixed):", hookV4);

        launcher.addDex(V4_POSITION_MANAGER, 0, V4_POOL_MANAGER, address(0), V4_PERMIT2, hookV4);

        vm.stopBroadcast();
    }

    function _mineHookSalt(bytes32 initCodeHash, uint160 requiredFlags, address deployerAddr) internal view returns (bytes32) {
        for (uint256 nonce = 0; ; nonce++) {
            bytes32 salt = bytes32(nonce);
            address predicted = vm.computeCreate2Address(salt, initCodeHash, deployerAddr);
            if (uint160(predicted) & 0x3FFF == requiredFlags) return salt;
        }
    }
}
