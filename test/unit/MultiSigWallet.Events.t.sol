// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {CodeConstants} from "../../script/CodeConstants.sol";
import {MultiSigWallet} from "../../src/MultiSigWallet.sol";
import {EthStipendSenderMock} from "../mocks/EthStipendSenderMock.sol";

import "../../src/events/MultiSigWalletEvents.sol";

/**
 * @dev Event-only tests for the MultiSigWallet events added by the refactor:
 *      MultiSigInitialized (constructor) and Deposit (receive, only for a non-zero value).
 */
contract MultiSigWalletEventsTest is BaseTest, CodeConstants {
    // =========================================================================
    //  Contracts and addresses
    // =========================================================================

    EthStipendSenderMock internal s_stipendSender;
    address internal s_depositor = makeAddr("depositor");

    // =========================================================================
    //  Constants
    // =========================================================================

    /// ETH sent to receive() in the Deposit tests
    uint256 constant DEPOSIT_AMOUNT = 0.5 ether;

    /// Number of owners of the freshly deployed wallet
    uint256 constant NEW_WALLET_OWNER_COUNT = 3;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();
        s_stipendSender = new EthStipendSenderMock();
        vm.deal(s_depositor, DEPOSIT_AMOUNT * 10);
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _newWalletOwners() internal pure returns (address[] memory owners) {
        owners = new address[](NEW_WALLET_OWNER_COUNT);
        owners[0] = ANVIL_OWNER_1;
        owners[1] = ANVIL_OWNER_2;
        owners[2] = ANVIL_OWNER_3;
    }

    /// @dev Asserts exactly one Deposit(`_sender`, `_value`) was emitted by the wallet.
    function _assertSingleDeposit(
        Vm.Log[] memory _logs,
        address _sender,
        uint256 _value
    ) internal view {
        uint256 count;
        for (uint256 i = 0; i < _logs.length; i++) {
            if (
                _logs[i].emitter != address(multiSigWallet) ||
                _logs[i].topics[0] != Deposit.selector
            ) continue;

            count++;
            assertEq(
                address(uint160(uint256(_logs[i].topics[1]))),
                _sender,
                "Deposit must log the sender"
            );
            assertEq(
                abi.decode(_logs[i].data, (uint256)),
                _value,
                "Deposit must log the value"
            );
        }
        assertEq(count, 1, "Deposit must be emitted exactly once");
    }

    /// @dev Asserts the wallet emitted no log at all.
    function _assertNoWalletLog(Vm.Log[] memory _logs) internal view {
        for (uint256 i = 0; i < _logs.length; i++) {
            assertTrue(
                _logs[i].emitter != address(multiSigWallet),
                "a zero-value send must not emit any wallet log"
            );
        }
    }

    // =========================================================================
    //  constructor — MultiSigInitialized
    // =========================================================================

    function testConstructorEmitsMultiSigInitialized() public {
        address[] memory owners = _newWalletOwners();

        vm.recordLogs();
        MultiSigWallet wallet = new MultiSigWallet(
            owners,
            MULTISIG_REQUIRED_CONFIRMATIONS
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter != address(wallet) ||
                logs[i].topics[0] != MultiSigInitialized.selector
            ) continue;

            eventFound = true;
            assertEq(
                logs[i].topics.length,
                1,
                "MultiSigInitialized has no indexed params"
            );
            (address[] memory loggedOwners, uint256 required) = abi.decode(
                logs[i].data,
                (address[], uint256)
            );
            assertEq(loggedOwners.length, owners.length, "owners length");
            for (uint256 j = 0; j < owners.length; j++) {
                assertEq(loggedOwners[j], owners[j], "owner mismatch");
            }
            assertEq(
                required,
                MULTISIG_REQUIRED_CONFIRMATIONS,
                "required confirmations"
            );
            assertEq(
                required,
                wallet.getRequiredConfirmations(),
                "logged required must match the wallet"
            );
            break;
        }
        assertTrue(eventFound, "MultiSigInitialized event was not emitted");
    }

    // =========================================================================
    //  receive — Deposit
    // =========================================================================

    function testReceiveEmitsDepositOnPlainEthSend() public {
        uint256 balanceBefore = address(multiSigWallet).balance;

        vm.recordLogs();
        vm.prank(s_depositor);
        (bool success, ) = address(multiSigWallet).call{value: DEPOSIT_AMOUNT}(
            ""
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(success, "plain ETH send must succeed");
        assertEq(
            address(multiSigWallet).balance - balanceBefore,
            DEPOSIT_AMOUNT,
            "wallet balance must increase by the deposit"
        );
        _assertSingleDeposit(logs, s_depositor, DEPOSIT_AMOUNT);
    }

    function testReceiveEmitsDepositWithTransferStipend() public {
        uint256 balanceBefore = address(multiSigWallet).balance;

        vm.recordLogs();
        vm.prank(s_depositor);
        s_stipendSender.sendWithTransfer{value: DEPOSIT_AMOUNT}(
            payable(address(multiSigWallet))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            address(multiSigWallet).balance - balanceBefore,
            DEPOSIT_AMOUNT,
            "transfer with 2300 gas stipend must succeed"
        );
        _assertSingleDeposit(logs, address(s_stipendSender), DEPOSIT_AMOUNT);
    }

    function testReceiveEmitsDepositWithSendStipend() public {
        uint256 balanceBefore = address(multiSigWallet).balance;

        vm.recordLogs();
        vm.prank(s_depositor);
        bool success = s_stipendSender.sendWithSend{value: DEPOSIT_AMOUNT}(
            payable(address(multiSigWallet))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(success, "send with 2300 gas stipend must succeed");
        assertEq(
            address(multiSigWallet).balance - balanceBefore,
            DEPOSIT_AMOUNT,
            "wallet balance must increase by the deposit"
        );
        _assertSingleDeposit(logs, address(s_stipendSender), DEPOSIT_AMOUNT);
    }

    function testReceiveZeroValuePlainCallSucceedsWithoutDeposit() public {
        uint256 balanceBefore = address(multiSigWallet).balance;

        vm.recordLogs();
        vm.prank(s_depositor);
        (bool success, ) = address(multiSigWallet).call{value: 0}("");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(success, "zero-value plain send must succeed");
        assertEq(
            address(multiSigWallet).balance,
            balanceBefore,
            "wallet balance must not change"
        );
        _assertNoWalletLog(logs);
    }

    function testReceiveZeroValueTransferSucceedsWithoutDeposit() public {
        uint256 balanceBefore = address(multiSigWallet).balance;

        vm.recordLogs();
        vm.prank(s_depositor);
        s_stipendSender.sendWithTransfer{value: 0}(
            payable(address(multiSigWallet))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            address(multiSigWallet).balance,
            balanceBefore,
            "wallet balance must not change"
        );
        _assertNoWalletLog(logs);
    }

    function testReceiveZeroValueSendSucceedsWithoutDeposit() public {
        vm.recordLogs();
        vm.prank(s_depositor);
        bool success = s_stipendSender.sendWithSend{value: 0}(
            payable(address(multiSigWallet))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(success, "zero-value send must succeed");
        _assertNoWalletLog(logs);
    }

    function testReceiveOneWeiEmitsDeposit() public {
        vm.recordLogs();
        vm.prank(s_depositor);
        (bool success, ) = address(multiSigWallet).call{value: 1}("");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(success, "one-wei send must succeed");
        _assertSingleDeposit(logs, s_depositor, 1);
    }
}
