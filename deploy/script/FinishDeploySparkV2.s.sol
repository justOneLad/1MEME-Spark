// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme

import {Script, console2} from "forge-std/Script.sol";
import {SparkLauncherV2} from "spark-v2-contracts/SparkLauncherV2.sol";
import {SparkHookV4} from "spark-v2-contracts/hooks/SparkHookV4.sol";
import {SparkHookInfinity} from "spark-v2-contracts/hooks/SparkHookInfinity.sol";
import {SparkBurner} from "spark-v2-contracts/SparkBurner.sol";

contract FinishDeploySparkV2 is Script {
    address constant LAUNCHER = 0xcD5B9F286cd5A2cE2fBe160bAfc018a1159d5c77;

    address constant V4_POSITION_MANAGER = 0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b;
    address constant V4_POOL_MANAGER     = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant V4_PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant INF_POSITION_MANAGER = 0x55f4c8abA71A1e923edC303eb4fEfF14608cC226;
    address constant INF_VAULT            = 0x238a358808379702088667322f80aC48bAd5e6c4;
    address constant INF_CL_POOL_MANAGER  = 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b;
    address constant INF_PERMIT2          = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;

    function run() external returns (address hookV4, address hookInfinity, address burner) {
        vm.startBroadcast();
        address deployer = msg.sender;

        SparkLauncherV2 launcher = SparkLauncherV2(payable(LAUNCHER));
        require(launcher.owner() == deployer, "not the owner of this launcher");
        require(address(launcher.locker()) != address(0), "launcher not wired to a locker");

        bytes memory hookV4Code = abi.encodePacked(
            type(SparkHookV4).creationCode,
            abi.encode(V4_POOL_MANAGER, LAUNCHER, deployer)
        );
        bytes32 hookV4InitCodeHash = keccak256(hookV4Code);
        bytes32 hookV4Salt = _mineHookSalt(hookV4InitCodeHash, 0xC4);
        hookV4 = address(new SparkHookV4{salt: hookV4Salt}(V4_POOL_MANAGER, LAUNCHER, deployer));
        require(uint160(hookV4) & 0x3FFF == 0xC4, "hookV4 permission bits mismatch");
        console2.log("SparkHookV4       :", hookV4);

        launcher.addDex(V4_POSITION_MANAGER, 0, V4_POOL_MANAGER, address(0), V4_PERMIT2, hookV4);

        hookInfinity = address(new SparkHookInfinity(INF_CL_POOL_MANAGER, LAUNCHER, deployer));
        require(
            SparkHookInfinity(payable(hookInfinity)).getHooksRegistrationBitmap()
                == SparkHookInfinity(payable(hookInfinity)).REQUIRED_BITMAP(),
            "hookInfinity bitmap mismatch"
        );
        console2.log("SparkHookInfinity :", hookInfinity);

        launcher.addDex(INF_POSITION_MANAGER, 1, INF_VAULT, INF_CL_POOL_MANAGER, INF_PERMIT2, hookInfinity);

        burner = address(new SparkBurner());
        console2.log("SparkBurner       :", burner);

        launcher.setBurner(burner);

        vm.stopBroadcast();
    }

    function _mineHookSalt(bytes32 initCodeHash, uint160 requiredFlags) internal view returns (bytes32) {
        for (uint256 nonce = 0; ; nonce++) {
            bytes32 salt = bytes32(nonce);
            address predicted = vm.computeCreate2Address(salt, initCodeHash);
            if (uint160(predicted) & 0x3FFF == requiredFlags) return salt;
        }
    }
}
