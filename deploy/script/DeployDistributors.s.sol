// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Deploys the two independent distributor utilities — no relation to any
// Spark launcher, and no chain-specific addresses needed, so this one script
// runs unchanged on any chain. MultiSender is plain and stateless (no init).
// MerkleDistributor is UUPS-upgradeable behind a proxy, initialized with an
// unset feeWallet (defaults to owner) and the same vanity campaignFee used
// as launchFee across every Spark launcher.

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MultiSender} from "distributor-contracts/MultiSender.sol";
import {MerkleDistributor} from "distributor-contracts/MerkleDistributor.sol";

contract DeployDistributors is Script {
    uint256 constant CAMPAIGN_FEE = 0.001111 ether;
    uint256 constant TX_DELAY_MS = 10000;

    function run() external returns (address multiSender, address merkleDistributorProxy) {
        vm.startBroadcast();

        multiSender = address(new MultiSender());
        console2.log("MultiSender               :", multiSender);
        vm.sleep(TX_DELAY_MS);

        MerkleDistributor impl = new MerkleDistributor();
        console2.log("MerkleDistributor impl    :", address(impl));
        vm.sleep(TX_DELAY_MS);

        bytes memory initData = abi.encodeCall(MerkleDistributor.initialize, (address(0), CAMPAIGN_FEE));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        merkleDistributorProxy = address(proxy);
        console2.log("MerkleDistributor proxy   :", merkleDistributorProxy);

        vm.stopBroadcast();
    }
}
