// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Independent, protocol-agnostic claim-based distributor — no relation to any
// Spark launcher. UUPS-upgradeable (unlike MultiSender.sol's plain, ownerless
// design in this same folder) because this one does hold funds across
// long-lived campaigns and does have an owner, so the same "state that
// persists and might need a fix without redeploying" reasoning that justifies
// upgradeability for the launchers applies here too.
//
// One contract, many campaigns, open to anyone: any caller opens a campaign
// per token (or native currency) with a Merkle root committing to every
// (index, account, amount) allocation, funds it in the same transaction, and
// each recipient (or anyone claiming on their behalf — funds always go to the
// committed `account`, never to msg.sender) submits a proof to claim. Each
// campaign's `remaining` balance is tracked independently so multiple
// campaigns sharing one contract, including several native-funded ones,
// never mix accounting.
//
// createCampaign charges a flat native listing fee (always native regardless
// of the campaign's own token, same convention as SparkLauncher's launchFee)
// — this funds the off-chain indexing/API work needed to actually surface
// other people's campaigns/drops, since nothing else about this contract
// requires the platform to do anything after a campaign is created. Only
// that campaign's own `creator` can sweep its unclaimed remainder after the
// deadline — the platform's cut is the upfront fee, it never has a claim on
// distribution funds it didn't fund itself.

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleDistributor is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    struct Campaign {
        address creator;
        address token;       // address(0) = native
        bytes32 merkleRoot;
        uint256 deadline;    // sweep() is callable by the creator only after this
        uint256 remaining;
        bool    swept;
    }

    error ZeroRoot();
    error DeadlineInPast();
    error ValueMismatch();
    error TransferFailed();
    error CampaignNotFound();
    error AlreadyClaimed();
    error InvalidProof();
    error InsufficientRemaining();
    error DeadlineNotPassed();
    error AlreadySwept();
    error NotCreator();

    Campaign[] public campaigns;
    mapping(uint256 => mapping(uint256 => uint256)) private _claimedBitMap;

    address public feeWallet;
    uint256 public campaignFee;

    event CampaignCreated(uint256 indexed campaignId, address indexed creator, address indexed token, bytes32 merkleRoot, uint256 amount, uint256 deadline);
    event Claimed(uint256 indexed campaignId, uint256 index, address indexed account, uint256 amount);
    event Swept(uint256 indexed campaignId, address indexed to, uint256 amount);
    event FeeWalletSet(address indexed wallet);
    event CampaignFeeSet(uint256 fee);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address feeWallet_, uint256 campaignFee_) external initializer {
        __Ownable_init(msg.sender);
        feeWallet = feeWallet_;
        campaignFee = campaignFee_;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setFeeWallet(address wallet_) external onlyOwner {
        feeWallet = wallet_;
        emit FeeWalletSet(wallet_);
    }

    function setCampaignFee(uint256 fee_) external onlyOwner {
        campaignFee = fee_;
        emit CampaignFeeSet(fee_);
    }

    function _feeRecipient() private view returns (address) {
        return feeWallet == address(0) ? owner() : feeWallet;
    }

    function createCampaign(address token_, bytes32 merkleRoot_, uint256 amount_, uint256 deadline_)
        external payable returns (uint256 campaignId)
    {
        if (merkleRoot_ == bytes32(0)) revert ZeroRoot();
        if (deadline_ <= block.timestamp) revert DeadlineInPast();

        if (token_ == address(0)) {
            if (msg.value != amount_ + campaignFee) revert ValueMismatch();
        } else {
            if (msg.value != campaignFee) revert ValueMismatch();
            _safeTransferFrom(token_, msg.sender, address(this), amount_);
        }

        if (campaignFee > 0) {
            (bool ok,) = _feeRecipient().call{value: campaignFee}("");
            if (!ok) revert TransferFailed();
        }

        campaignId = campaigns.length;
        campaigns.push(Campaign({creator: msg.sender, token: token_, merkleRoot: merkleRoot_, deadline: deadline_, remaining: amount_, swept: false}));
        emit CampaignCreated(campaignId, msg.sender, token_, merkleRoot_, amount_, deadline_);
    }

    function claim(uint256 campaignId_, uint256 index_, address account_, uint256 amount_, bytes32[] calldata merkleProof_) external {
        if (campaignId_ >= campaigns.length) revert CampaignNotFound();
        Campaign storage c = campaigns[campaignId_];
        if (isClaimed(campaignId_, index_)) revert AlreadyClaimed();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(index_, account_, amount_))));
        if (!MerkleProof.verify(merkleProof_, c.merkleRoot, leaf)) revert InvalidProof();
        if (amount_ > c.remaining) revert InsufficientRemaining();

        _setClaimed(campaignId_, index_);
        c.remaining -= amount_;

        if (c.token == address(0)) {
            (bool ok,) = account_.call{value: amount_}("");
            if (!ok) revert TransferFailed();
        } else {
            _safeTransfer(c.token, account_, amount_);
        }

        emit Claimed(campaignId_, index_, account_, amount_);
    }

    function sweep(uint256 campaignId_, address to_) external {
        if (campaignId_ >= campaigns.length) revert CampaignNotFound();
        Campaign storage c = campaigns[campaignId_];
        if (msg.sender != c.creator) revert NotCreator();
        if (block.timestamp < c.deadline) revert DeadlineNotPassed();
        if (c.swept) revert AlreadySwept();

        uint256 amount = c.remaining;
        c.remaining = 0;
        c.swept = true;

        if (amount > 0) {
            if (c.token == address(0)) {
                (bool ok,) = to_.call{value: amount}("");
                if (!ok) revert TransferFailed();
            } else {
                _safeTransfer(c.token, to_, amount);
            }
        }

        emit Swept(campaignId_, to_, amount);
    }

    function isClaimed(uint256 campaignId_, uint256 index_) public view returns (bool) {
        uint256 wordIndex = index_ / 256;
        uint256 bitIndex = index_ % 256;
        uint256 word = _claimedBitMap[campaignId_][wordIndex];
        return (word >> bitIndex) & 1 == 1;
    }

    function campaignCount() external view returns (uint256) {
        return campaigns.length;
    }

    function _setClaimed(uint256 campaignId_, uint256 index_) private {
        uint256 wordIndex = index_ / 256;
        uint256 bitIndex = index_ % 256;
        _claimedBitMap[campaignId_][wordIndex] |= (1 << bitIndex);
    }

    function _safeTransfer(address token_, address to_, uint256 amount_) private {
        (bool ok, bytes memory data) = token_.call(abi.encodeWithSelector(0xa9059cbb, to_, amount_));
        if (!ok || (data.length > 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _safeTransferFrom(address token_, address from_, address to_, uint256 amount_) private {
        (bool ok, bytes memory data) = token_.call(abi.encodeWithSelector(0x23b872dd, from_, to_, amount_));
        if (!ok || (data.length > 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
