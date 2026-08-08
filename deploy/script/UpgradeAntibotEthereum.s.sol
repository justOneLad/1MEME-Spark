// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Owner-only upgrade of the live Ethereum SparkLauncher/SparkGo proxies: fresh
// SparkToken/SparkGoHookV4 impls (3% max-wallet, 30-min window, no hook-level
// max-buy), UUPS-upgrade both launchers, setTokenImpl, repoint the v4 DEX
// entry via addDex (no PancakeSwap Infinity on Ethereum). Future launches only.

import {Script, console2} from "forge-std/Script.sol";
import {SparkToken} from "spark-contracts/SparkToken.sol";
import {SparkLauncher} from "spark-contracts/SparkLauncherUpgradeable.sol";
import {SparkGoLauncher} from "spark-go-contracts/SparkGoLauncher.sol";
import {SparkGoHookV4} from "spark-go-contracts/hooks/SparkGoHookV4.sol";
import {SparkGoHookFactory} from "./SparkGoHookFactory.sol";

contract UpgradeAntibotEthereum is Script {
    address constant SPARK_LAUNCHER_PROXY = 0x1010B4593376A5eEc045F9A706F615ed8417f541;
    address constant SPARKGO_PROXY        = 0x1655d6d3D2A6a29cf17bC151eDeA50A14A5DC918;

    address constant UNISWAP_V4_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address constant UNISWAP_V4_POOL_MANAGER     = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant PERMIT2                     = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

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

        goLauncher.addDex(UNISWAP_V4_POSITION_MANAGER, 0, UNISWAP_V4_POOL_MANAGER, address(0), PERMIT2, newHookV4);
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
