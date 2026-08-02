// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockUUPSV1, MockUUPSV2} from "./mocks/MockUUPS.sol";

contract ProxyUpgradeTest is Test {
    function test_initializeSetsStorageThroughProxy() public {
        MockUUPSV1 impl = new MockUUPSV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(MockUUPSV1.initialize, (42)));
        MockUUPSV1 wrapped = MockUUPSV1(address(proxy));

        assertEq(wrapped.value(), 42);
        assertEq(wrapped.owner(), address(this));
        assertEq(wrapped.version(), "v1");
    }

    function test_implementationCannotBeInitializedDirectly() public {
        MockUUPSV1 impl = new MockUUPSV1();
        vm.expectRevert();
        impl.initialize(1);
    }

    function test_upgradePreservesStorage() public {
        MockUUPSV1 implV1 = new MockUUPSV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), abi.encodeCall(MockUUPSV1.initialize, (7)));
        MockUUPSV1 wrapped = MockUUPSV1(address(proxy));

        MockUUPSV2 implV2 = new MockUUPSV2();
        wrapped.upgradeToAndCall(address(implV2), "");

        MockUUPSV2 wrappedV2 = MockUUPSV2(address(proxy));
        assertEq(wrappedV2.value(), 7, "storage must survive the upgrade");
        assertEq(wrappedV2.version(), "v2", "logic must reflect the new implementation");

        wrappedV2.bump();
        assertEq(wrappedV2.value(), 8);
    }

    function test_onlyOwnerCanUpgrade() public {
        MockUUPSV1 implV1 = new MockUUPSV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), abi.encodeCall(MockUUPSV1.initialize, (1)));
        MockUUPSV1 wrapped = MockUUPSV1(address(proxy));
        MockUUPSV2 implV2 = new MockUUPSV2();

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        wrapped.upgradeToAndCall(address(implV2), "");
    }
}
