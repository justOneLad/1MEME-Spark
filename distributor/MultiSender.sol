// SPDX-License-Identifier: MIT
pragma solidity ^0.8.32;

// 1MEME Spark — 1coin.meme
//
// Protocol-agnostic batch sender. Permissionless, stateless: fans out the
// caller's own funds in one transaction and holds nothing afterward. No
// owner, no persistent balance, no reentrancy surface.

contract MultiSender {
    error LengthMismatch();
    error EmptyRecipients();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientValue();
    error TransferFailed();

    function disperseEther(address[] calldata recipients, uint256[] calldata amounts) external payable {
        uint256 n = recipients.length;
        if (n != amounts.length) revert LengthMismatch();
        if (n == 0) revert EmptyRecipients();

        uint256 total;
        for (uint256 i; i < n; ++i) {
            total += amounts[i];
        }
        if (total > msg.value) revert InsufficientValue();

        for (uint256 i; i < n; ++i) {
            _sendEther(recipients[i], amounts[i]);
        }
        _refundRemainder(total);
    }

    function disperseEtherEqual(address[] calldata recipients, uint256 amountEach) external payable {
        uint256 n = recipients.length;
        if (n == 0) revert EmptyRecipients();
        if (amountEach == 0) revert ZeroAmount();

        uint256 total = amountEach * n;
        if (total > msg.value) revert InsufficientValue();

        for (uint256 i; i < n; ++i) {
            _sendEther(recipients[i], amountEach);
        }
        _refundRemainder(total);
    }

    function disperseToken(address token, address[] calldata recipients, uint256[] calldata amounts) external {
        uint256 n = recipients.length;
        if (n != amounts.length) revert LengthMismatch();
        if (n == 0) revert EmptyRecipients();

        for (uint256 i; i < n; ++i) {
            _safeTransferFrom(token, recipients[i], amounts[i]);
        }
    }

    function disperseTokenEqual(address token, address[] calldata recipients, uint256 amountEach) external {
        uint256 n = recipients.length;
        if (n == 0) revert EmptyRecipients();
        if (amountEach == 0) revert ZeroAmount();

        for (uint256 i; i < n; ++i) {
            _safeTransferFrom(token, recipients[i], amountEach);
        }
    }

    function _sendEther(address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function _refundRemainder(uint256 total) private {
        uint256 remainder = msg.value - total;
        if (remainder == 0) return;
        (bool ok,) = msg.sender.call{value: remainder}("");
        if (!ok) revert TransferFailed();
    }

    function _safeTransferFrom(address token_, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) return;
        (bool ok, bytes memory data) = token_.call(abi.encodeWithSelector(0x23b872dd, msg.sender, to, amount));
        if (!ok || (data.length > 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
