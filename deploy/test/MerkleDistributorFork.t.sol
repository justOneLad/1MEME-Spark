// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Fork} from "./Fork.t.sol";
import {MerkleDistributor} from "distributor-contracts/MerkleDistributor.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

contract MerkleDistributorForkTest is Fork {
    MerkleDistributor dist;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address carol = address(0xCA401);
    address dave  = address(0xDA4E);

    uint256 amtAlice = 1 ether;
    uint256 amtBob   = 2 ether;
    uint256 amtCarol = 3 ether;
    uint256 amtDave  = 4 ether;

    bytes32 leafAlice; bytes32 leafBob; bytes32 leafCarol; bytes32 leafDave;
    bytes32 nodeAB; bytes32 nodeCD; bytes32 root;

    function setUp() public override {
        super.setUp();

        MerkleDistributor impl = new MerkleDistributor();
        bytes memory initData = abi.encodeCall(MerkleDistributor.initialize, (address(0), 0));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        dist = MerkleDistributor(payable(address(proxy)));

        leafAlice = _leaf(0, alice, amtAlice);
        leafBob   = _leaf(1, bob, amtBob);
        leafCarol = _leaf(2, carol, amtCarol);
        leafDave  = _leaf(3, dave, amtDave);
        nodeAB = _hashPair(leafAlice, leafBob);
        nodeCD = _hashPair(leafCarol, leafDave);
        root = _hashPair(nodeAB, nodeCD);
    }

    function test_nativeCampaign_claimSucceedsAndPaysAccount() public {
        uint256 total = amtAlice + amtBob + amtCarol + amtDave;
        vm.deal(address(this), total);
        uint256 campaignId = dist.createCampaign{value: total}(address(0), root, total, block.timestamp + 7 days);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafBob; proof[1] = nodeCD;

        uint256 balBefore = alice.balance;
        dist.claim(campaignId, 0, alice, amtAlice, proof);
        assertEq(alice.balance - balBefore, amtAlice);
        assertTrue(dist.isClaimed(campaignId, 0));
    }

    function test_claim_revertsOnDoubleClaim() public {
        uint256 total = amtAlice + amtBob + amtCarol + amtDave;
        vm.deal(address(this), total);
        uint256 campaignId = dist.createCampaign{value: total}(address(0), root, total, block.timestamp + 7 days);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafBob; proof[1] = nodeCD;
        dist.claim(campaignId, 0, alice, amtAlice, proof);

        vm.expectRevert(MerkleDistributor.AlreadyClaimed.selector);
        dist.claim(campaignId, 0, alice, amtAlice, proof);
    }

    function test_claim_revertsOnWrongProof() public {
        uint256 total = amtAlice + amtBob + amtCarol + amtDave;
        vm.deal(address(this), total);
        uint256 campaignId = dist.createCampaign{value: total}(address(0), root, total, block.timestamp + 7 days);

        // proof for bob's leaf, submitted for alice's index/amount — must fail.
        bytes32[] memory wrongProof = new bytes32[](2);
        wrongProof[0] = leafAlice; wrongProof[1] = nodeCD;

        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        dist.claim(campaignId, 0, alice, amtAlice, wrongProof);
    }

    function test_erc20Campaign_realUsdt() public {
        uint256 total = amtAlice + amtBob + amtCarol + amtDave;
        deal(USDT, address(this), total);
        IERC20(USDT).approve(address(dist), total);
        uint256 campaignId = dist.createCampaign(USDT, root, total, block.timestamp + 7 days);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafAlice; proof[1] = nodeCD;
        dist.claim(campaignId, 1, bob, amtBob, proof);

        assertEq(IERC20(USDT).balanceOf(bob), amtBob);
    }

    function test_sweep_revertsBeforeDeadline() public {
        uint256 total = amtAlice + amtBob + amtCarol + amtDave;
        vm.deal(address(this), total);
        uint256 campaignId = dist.createCampaign{value: total}(address(0), root, total, block.timestamp + 7 days);

        vm.expectRevert(MerkleDistributor.DeadlineNotPassed.selector);
        dist.sweep(campaignId, address(this));
    }

    function test_sweep_afterDeadline_recoversOnlyThatCampaignsUnclaimedFunds() public {
        uint256 total = amtAlice + amtBob + amtCarol + amtDave;
        vm.deal(address(this), total);
        uint256 campaignId = dist.createCampaign{value: total}(address(0), root, total, block.timestamp + 1 days);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafBob; proof[1] = nodeCD;
        dist.claim(campaignId, 0, alice, amtAlice, proof); // alice claims, rest goes unclaimed

        vm.warp(block.timestamp + 2 days);
        uint256 balBefore = address(this).balance;
        dist.sweep(campaignId, address(this));
        assertEq(address(this).balance - balBefore, total - amtAlice, "sweep must recover exactly the unclaimed remainder");

        vm.expectRevert(MerkleDistributor.AlreadySwept.selector);
        dist.sweep(campaignId, address(this));
    }

    function test_multipleCampaigns_accountingNeverMixes() public {
        // Two independent native campaigns sharing one contract; sweeping one must not touch the other.
        uint256 total = amtAlice + amtBob + amtCarol + amtDave;
        vm.deal(address(this), total * 2);
        uint256 c1 = dist.createCampaign{value: total}(address(0), root, total, block.timestamp + 1 days);
        uint256 c2 = dist.createCampaign{value: total}(address(0), root, total, block.timestamp + 30 days);

        vm.warp(block.timestamp + 2 days);
        uint256 balBefore = address(this).balance;
        dist.sweep(c1, address(this));
        assertEq(address(this).balance - balBefore, total, "only campaign 1's funds swept");

        vm.expectRevert(MerkleDistributor.DeadlineNotPassed.selector);
        dist.sweep(c2, address(this));

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leafBob; proof[1] = nodeCD;
        dist.claim(c2, 0, alice, amtAlice, proof); // campaign 2 must still be fully funded/claimable
    }

    function test_anyoneCanCreateACampaign() public {
        address randomCreator = address(0xF00D);
        vm.deal(randomCreator, 1 ether);
        vm.prank(randomCreator);
        uint256 campaignId = dist.createCampaign{value: 1 ether}(address(0), root, 1 ether, block.timestamp + 7 days);
        (address creator,,,,,) = dist.campaigns(campaignId);
        assertEq(creator, randomCreator, "creator must be recorded as whoever actually called createCampaign");
    }

    function test_onlyCampaignCreatorCanSweepIt() public {
        uint256 total = amtAlice + amtBob + amtCarol + amtDave;
        vm.deal(address(this), total);
        uint256 campaignId = dist.createCampaign{value: total}(address(0), root, total, block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days);

        vm.prank(address(0xBAD));
        vm.expectRevert(MerkleDistributor.NotCreator.selector);
        dist.sweep(campaignId, address(0xBAD));

        dist.sweep(campaignId, address(this)); // the actual creator (this test contract) can
    }

    function test_campaignFee_chargedOnCreation_nativeCampaign() public {
        vm.prank(dist.owner());
        dist.setCampaignFee(0.01 ether);
        address platformFeeWallet = address(0xFEE5);
        vm.prank(dist.owner());
        dist.setFeeWallet(platformFeeWallet);

        uint256 fundAmount = 4 ether;
        vm.deal(address(this), fundAmount + 0.01 ether);
        uint256 feeBalBefore = platformFeeWallet.balance;
        uint256 campaignId = dist.createCampaign{value: fundAmount + 0.01 ether}(address(0), root, fundAmount, block.timestamp + 7 days);

        assertEq(platformFeeWallet.balance - feeBalBefore, 0.01 ether, "fee must go to the fee wallet");
        (, , , , uint256 remaining, ) = dist.campaigns(campaignId);
        assertEq(remaining, fundAmount, "fee must not eat into the campaign's own distributable amount");
    }

    function test_campaignFee_chargedOnCreation_erc20Campaign() public {
        vm.prank(dist.owner());
        dist.setCampaignFee(0.01 ether);

        address randomCreator = address(0xF00D2);
        uint256 fundAmount = 4 ether;
        deal(USDT, randomCreator, fundAmount);
        vm.deal(randomCreator, 0.01 ether);
        vm.startPrank(randomCreator);
        IERC20(USDT).approve(address(dist), fundAmount);

        uint256 feeBalBefore = dist.owner().balance; // feeWallet unset -> defaults to owner(), distinct from randomCreator
        dist.createCampaign{value: 0.01 ether}(USDT, root, fundAmount, block.timestamp + 7 days);
        vm.stopPrank();
        assertEq(dist.owner().balance - feeBalBefore, 0.01 ether, "fee for a token campaign is still paid in native currency");
    }

    function test_campaignFee_revertsIfNotIncluded() public {
        vm.prank(dist.owner());
        dist.setCampaignFee(0.01 ether);

        vm.deal(address(this), 1 ether);
        vm.expectRevert(MerkleDistributor.ValueMismatch.selector);
        dist.createCampaign{value: 1 ether}(address(0), root, 1 ether, block.timestamp + 7 days); // missing the extra 0.01 ether fee
    }

    function _leaf(uint256 index, address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    receive() external payable {}
}
