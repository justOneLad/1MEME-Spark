// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Owner-only upgrade of the live BSC SparkLauncher/SparkGo proxies: fresh
// SparkToken/hook impls (3% max-wallet, 30-min window, no hook-level max-buy),
// UUPS-upgrade both launchers, setTokenImpl, repoint DEX entries via addDex.
// Only affects future launches.

import {Script, console2} from "forge-std/Script.sol";
import {SparkToken} from "spark-contracts/SparkToken.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {SparkGoHookV4} from "spark-go-contracts/hooks/SparkGoHookV4.sol";
import {SparkGoHookInfinity} from "spark-go-contracts/hooks/SparkGoHookInfinity.sol";
import {SparkGoHookFactory} from "./SparkGoHookFactory.sol";

contract UpgradeAntibotBSC is Script {
    address constant SPARK_LAUNCHER_PROXY = 0xC10b8647B7d0d88B77C0A9FfAD5C7C17564B1973;
    address constant SPARKGO_PROXY        = 0xC0d33846D04F5Ce0a34AEecE9b6462433EBC8f7C;

    address constant UNISWAP_V4_POSITION_MANAGER = 0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b;
    address constant UNISWAP_V4_POOL_MANAGER     = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant UNISWAP_V4_PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant INF_POSITION_MANAGER = 0x55f4c8abA71A1e923edC303eb4fEfF14608cC226;
    address constant INF_VAULT            = 0x238a358808379702088667322f80aC48bAd5e6c4;
    address constant INF_CL_POOL_MANAGER  = 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b;
    address constant INF_PERMIT2          = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;

    uint256 constant TX_DELAY_MS = 10000;

    function run() external {
        vm.startBroadcast();
        address deployer = msg.sender;

        SparkToken newTokenImpl = new SparkToken();
        console2.log("new SparkToken impl :", address(newTokenImpl));
        vm.sleep(TX_DELAY_MS);

        SparkLauncher newLauncherImpl = new SparkLauncher();
        console2.log("new SparkLauncher impl :", address(newLauncherImpl));
        vm.sleep(TX_DELAY_MS);

        SparkGoLauncher newGoLauncherImpl = new SparkGoLauncher();
        console2.log("new SparkGoLauncher impl :", address(newGoLauncherImpl));
        vm.sleep(TX_DELAY_MS);

        SparkGoHookFactory hookFactory = new SparkGoHookFactory();
        vm.sleep(TX_DELAY_MS);
        bytes memory hookCode = abi.encodePacked(
            type(SparkGoHookV4).creationCode,
            abi.encode(UNISWAP_V4_POOL_MANAGER, SPARKGO_PROXY, deployer)
        );
        bytes32 hookInitCodeHash = keccak256(hookCode);
        bytes32 hookSalt = _mineHookSalt(hookInitCodeHash, 0xC4, address(hookFactory));
        address newHookV4 = hookFactory.deploy(hookSalt, UNISWAP_V4_POOL_MANAGER, SPARKGO_PROXY, deployer, deployer);
        require(uint160(newHookV4) & 0x3FFF == 0xC4, "hook permission bits mismatch");
        require(SparkGoHookV4(payable(newHookV4)).owner() == deployer, "hook owner fixup failed");
        console2.log("new SparkGoHookV4 :", newHookV4);
        vm.sleep(TX_DELAY_MS);

        SparkGoHookInfinity newHookInfinity = new SparkGoHookInfinity(INF_CL_POOL_MANAGER, SPARKGO_PROXY, deployer);
        require(
            newHookInfinity.getHooksRegistrationBitmap() == newHookInfinity.REQUIRED_BITMAP(),
            "hookInfinity bitmap mismatch"
        );
        console2.log("new SparkGoHookInfinity :", address(newHookInfinity));
        vm.sleep(TX_DELAY_MS);

        SparkLauncher launcher = SparkLauncher(payable(SPARK_LAUNCHER_PROXY));
        SparkGoLauncher goLauncher = SparkGoLauncher(payable(SPARKGO_PROXY));

        launcher.upgradeToAndCall(address(newLauncherImpl), "");
        vm.sleep(TX_DELAY_MS);
        goLauncher.upgradeToAndCall(address(newGoLauncherImpl), "");
        vm.sleep(TX_DELAY_MS);

        launcher.setTokenImpl(address(newTokenImpl));
        vm.sleep(TX_DELAY_MS);
        goLauncher.setTokenImpl(address(newTokenImpl));
        vm.sleep(TX_DELAY_MS);

        goLauncher.addDex(UNISWAP_V4_POSITION_MANAGER, 0, UNISWAP_V4_POOL_MANAGER, address(0), UNISWAP_V4_PERMIT2, newHookV4);
        vm.sleep(TX_DELAY_MS);
        goLauncher.addDex(INF_POSITION_MANAGER, 1, INF_VAULT, INF_CL_POOL_MANAGER, INF_PERMIT2, address(newHookInfinity));
        vm.sleep(TX_DELAY_MS);

        vm.stopBroadcast();
    }

    function _mineHookSalt(bytes32 initCodeHash, uint160 requiredFlags, address deployerAddr) private view returns (bytes32 salt) {
        for (uint256 nonce; ; ++nonce) {
            salt = bytes32(nonce);
            address predicted = vm.computeCreate2Address(salt, initCodeHash, deployerAddr);
            if (uint160(predicted) & 0x3FFF == requiredFlags) return salt;
        }
    }
}
