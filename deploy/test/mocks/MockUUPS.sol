// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// Trivial UUPS implementations used only to prove the proxy/init/upgrade machinery in isolation.

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MockUUPSV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public value;

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 value_) external initializer {
        __Ownable_init(msg.sender);
        value = value_;
    }

    function version() external pure virtual returns (string memory) {
        return "v1";
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

contract MockUUPSV2 is MockUUPSV1 {
    function version() external pure override returns (string memory) {
        return "v2";
    }

    function bump() external {
        value += 1;
    }
}
