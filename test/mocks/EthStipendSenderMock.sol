// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Forwards ETH with the 2300-gas stipend of `transfer` and `send`, to check that a
 *      receiver's `receive()` stays cheap enough for legacy senders.
 */
contract EthStipendSenderMock {
    function sendWithTransfer(address payable _to) external payable {
        _to.transfer(msg.value);
    }

    function sendWithSend(address payable _to) external payable returns (bool) {
        return _to.send(msg.value);
    }
}
