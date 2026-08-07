// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

import {Fork} from "./Fork.t.sol";
import {MultiSender} from "distributor-contracts/MultiSender.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

/// @dev Reenters disperseEther using its own funds when it receives ETH — proves a malicious
/// recipient can't corrupt another call's accounting, since the contract holds no shared state.
contract ReentrantRecipient {
    MultiSender immutable sender;
    bool armed;
    uint256 public reenterReceived;

    constructor(MultiSender sender_) { sender = sender_; }

    function arm() external { armed = true; }

    receive() external payable {
        if (armed) {
            armed = false;
            address[] memory recipients = new address[](1);
            recipients[0] = address(this);
            sender.disperseEtherEqual{value: 1 ether}(recipients, 1 ether);
        } else {
            reenterReceived += msg.value;
        }
    }
}

contract MultiSenderForkTest is Fork {
    MultiSender sender;

    function setUp() public override {
        super.setUp();
        sender = new MultiSender();
    }

    function test_disperseEther_explicitAmounts_and_refundsRemainder() public {
        address[] memory recipients = new address[](3);
        recipients[0] = address(0xAA1);
        recipients[1] = address(0xAA2);
        recipients[2] = address(0xAA3);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        vm.deal(address(this), 100 ether);
        uint256 balBefore = address(this).balance;
        sender.disperseEther{value: 10 ether}(recipients, amounts);

        assertEq(recipients[0].balance, 1 ether);
        assertEq(recipients[1].balance, 2 ether);
        assertEq(recipients[2].balance, 3 ether);
        assertEq(balBefore - address(this).balance, 6 ether, "only the 6 ether actually sent should be spent, the rest refunded");
    }

    function test_disperseEtherEqual_refundsRemainder() public {
        address[] memory recipients = new address[](4);
        for (uint256 i; i < 4; ++i) recipients[i] = address(uint160(0xB000 + i));

        vm.deal(address(this), 100 ether);
        uint256 balBefore = address(this).balance;
        sender.disperseEtherEqual{value: 5 ether}(recipients, 1 ether);

        for (uint256 i; i < 4; ++i) assertEq(recipients[i].balance, 1 ether);
        assertEq(balBefore - address(this).balance, 4 ether);
    }

    function test_disperseEther_revertsOnLengthMismatch() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        vm.expectRevert(MultiSender.LengthMismatch.selector);
        sender.disperseEther(recipients, amounts);
    }

    function test_disperseEther_revertsOnInsufficientValue() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0xAA1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        vm.expectRevert(MultiSender.InsufficientValue.selector);
        sender.disperseEther{value: 0.5 ether}(recipients, amounts);
    }

    function test_disperseToken_explicitAmounts_realUsdt() public {
        deal(USDT, address(this), 100 ether);
        IERC20(USDT).approve(address(sender), 100 ether);

        address[] memory recipients = new address[](2);
        recipients[0] = address(0xCC1);
        recipients[1] = address(0xCC2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;

        sender.disperseToken(USDT, recipients, amounts);

        assertEq(IERC20(USDT).balanceOf(recipients[0]), 10 ether);
        assertEq(IERC20(USDT).balanceOf(recipients[1]), 20 ether);
        assertEq(IERC20(USDT).balanceOf(address(sender)), 0, "sender contract must never hold a balance");
    }

    function test_disperseTokenEqual_realUsdt() public {
        deal(USDT, address(this), 100 ether);
        IERC20(USDT).approve(address(sender), 100 ether);

        address[] memory recipients = new address[](3);
        recipients[0] = address(0xDD1);
        recipients[1] = address(0xDD2);
        recipients[2] = address(0xDD3);

        sender.disperseTokenEqual(USDT, recipients, 5 ether);

        for (uint256 i; i < 3; ++i) assertEq(IERC20(USDT).balanceOf(recipients[i]), 5 ether);
    }

    function test_reentrantRecipient_cannotCorruptOtherCalls() public {
        ReentrantRecipient attacker = new ReentrantRecipient(sender);
        attacker.arm();
        vm.deal(address(attacker), 1 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = address(attacker);

        vm.deal(address(this), 2 ether);
        sender.disperseEtherEqual{value: 1 ether}(recipients, 1 ether);

        // The reentrant call (funded by the attacker's own balance) completed independently and
        // paid the attacker again — no state was shared or corrupted between the two calls.
        assertEq(attacker.reenterReceived(), 1 ether);
    }

    receive() external payable {}
}
