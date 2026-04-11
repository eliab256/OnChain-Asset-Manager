// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {CodeConstants} from "../../script/CodeConstants.sol";
import {MultiSigWallet} from "../../src/MultiSigWallet.sol";

import "../../src/errors/MultiSigWalletErrors.sol";
import "../../src/events/MultiSigWalletEvents.sol";

// =============================================================================
//  helper contracts
// =============================================================================

/// @dev A call target whose `increment` function we can verify was executed.
contract CallTarget {
    uint256 public count;
    function increment() external {
        count++;
    }
    fallback() external payable {}
    receive() external payable {}
}

/// @dev Always reverts contract used to test MultiSig__TxFailed.
contract RevertingTarget {
    fallback() external payable {
        revert("RevertingTarget: always reverts");
    }
}

contract MultiSigWalletTest is BaseTest, CodeConstants {
    // Well-known private keys for Anvil accounts 1, 2, 3
    // (deterministic, same in every local Anvil instance)
    uint256 constant ANVIL_OWNER_1_PK =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant ANVIL_OWNER_2_PK =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant ANVIL_OWNER_3_PK =
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    // A PK/address that is NOT one of the MultiSig owners
    uint256 constant NON_OWNER_PK =
        0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

    // Expected number of owners deployed by HelperConfig/DeployPeriphery
    uint256 constant EXPECTED_OWNER_COUNT = 3;

    // Index positions inside the owners array
    uint256 constant OWNER_INDEX_0 = 0;
    uint256 constant OWNER_INDEX_1 = 1;
    uint256 constant OWNER_INDEX_2 = 2;

    // Used wherever we need a tx id that is guaranteed not to exist
    uint256 constant NONEXISTENT_TX_ID = type(uint256).max;

    // ETH amounts used across tests
    uint256 constant ETH_WALLET_FUND = 10 ether; // funded by DeployPeriphery
    uint256 constant ETH_SEND_AMOUNT = 1 ether; // value forwarded in a tx
    uint256 constant ETH_RECEIVE_AMOUNT = 0.5 ether; // sent to receive()

    uint256 constant REQUIRED = 2; // must equal MULTISIG_REQUIRED_CONFIRMATIONS

    // =========================================================================
    //  State
    // =========================================================================

    address nonOwner;
    CallTarget callTarget;
    RevertingTarget revertingTarget;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp(); // deploys everything via DeployPeriphery + BaseTest

        nonOwner = vm.addr(NON_OWNER_PK);
        callTarget = new CallTarget();
        revertingTarget = new RevertingTarget();

        // Sanity-check: make sure the constants mirror what was deployed
        assertEq(
            multiSigWallet.getRequiredConfirmations(),
            MULTISIG_REQUIRED_CONFIRMATIONS,
            "setUp: REQUIRED constant mismatch"
        );
    }

    // =========================================================================
    //  Internal helpers
    // =========================================================================

    /// @dev Submits a no-op tx (calls callTarget with no data) from ANVIL_OWNER_1.
    function _submitDummyTx() internal returns (uint256 txId) {
        vm.prank(ANVIL_OWNER_1);
        txId = multiSigWallet.submitTransaction(address(callTarget), 0, "");
    }

    /// @dev Submits a tx and collects the two confirmations needed for quorum.
    ///      Owner 1 submits, owner 1 confirms, owner 2 confirms.
    function _submitAndReachQuorum() internal returns (uint256 txId) {
        txId = _submitDummyTx();
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.confirmTransaction(txId);
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);
    }

    /// @dev Produces a valid EIP-712 off-chain confirmation signature.
    function _signConfirm(
        uint256 signerPk,
        address signerAddr,
        uint256 txId
    ) internal view returns (bytes memory sig) {
        bytes32 digest = multiSigWallet.getConfirmDigest(txId, signerAddr);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    // =========================================================================
    //  Constructor
    // =========================================================================

    function test_constructor_deploysWithCorrectOwnersAndThreshold()
        public
        view
    {
        address[] memory owners = multiSigWallet.getOwners();
        assertEq(owners.length, EXPECTED_OWNER_COUNT);
        assertEq(owners[OWNER_INDEX_0], ANVIL_OWNER_1);
        assertEq(owners[OWNER_INDEX_1], ANVIL_OWNER_2);
        assertEq(owners[OWNER_INDEX_2], ANVIL_OWNER_3);
        assertEq(
            multiSigWallet.getRequiredConfirmations(),
            MULTISIG_REQUIRED_CONFIRMATIONS
        );
    }

    function test_constructor_revert_emptyOwnersArray() public {
        address[] memory empty = new address[](0);
        vm.expectRevert(MultiSig__InvalidRequirement.selector);
        new MultiSigWallet(empty, 1);
    }

    function test_constructor_revert_zeroRequiredConfirmations() public {
        address[] memory owners = new address[](1);
        owners[0] = ANVIL_OWNER_1;
        vm.expectRevert(MultiSig__InvalidRequirement.selector);
        new MultiSigWallet(owners, 0);
    }

    function test_constructor_revert_requiredExceedsOwnerCount() public {
        address[] memory owners = new address[](1);
        owners[0] = ANVIL_OWNER_1;
        uint256 tooHighRequired = owners.length + 1;
        vm.expectRevert(MultiSig__InvalidRequirement.selector);
        new MultiSigWallet(owners, tooHighRequired);
    }

    function test_constructor_revert_zeroAddressOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = address(0); // invalid
        owners[1] = ANVIL_OWNER_2;
        vm.expectRevert(MultiSig__ZeroAddress.selector);
        new MultiSigWallet(owners, 1);
    }

    function test_constructor_revert_duplicateOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = ANVIL_OWNER_1;
        owners[1] = ANVIL_OWNER_1; // duplicate
        vm.expectRevert(MultiSig__OwnerNotUnique.selector);
        new MultiSigWallet(owners, 2);
    }

    // =========================================================================
    //  submitTransaction
    // =========================================================================

    function test_submitTransaction_storesCorrectDataAndEmitsEvent() public {
        bytes memory data = abi.encodeWithSelector(
            CallTarget.increment.selector
        );
        uint256 expectedTxId = multiSigWallet.getTransactionCount();

        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(
            expectedTxId,
            ANVIL_OWNER_1,
            address(callTarget),
            ETH_SEND_AMOUNT,
            data
        );

        vm.prank(ANVIL_OWNER_1);
        uint256 txId = multiSigWallet.submitTransaction(
            address(callTarget),
            ETH_SEND_AMOUNT,
            data
        );

        assertEq(txId, expectedTxId);
        assertEq(multiSigWallet.getTransactionCount(), expectedTxId + 1);

        (
            address target,
            uint256 value,
            bytes memory storedData,
            bool executed,
            uint256 confirmations
        ) = multiSigWallet.getTransaction(txId);

        assertEq(target, address(callTarget));
        assertEq(value, ETH_SEND_AMOUNT);
        assertEq(storedData, data);
        assertFalse(executed);
        assertEq(confirmations, 0);
    }

    function test_submitTransaction_revert_callerIsNotOwner() public {
        vm.expectRevert(MultiSig__NotOwner.selector);
        vm.prank(nonOwner);
        multiSigWallet.submitTransaction(address(callTarget), 0, "");
    }

    // =========================================================================
    //  confirmTransaction
    // =========================================================================

    function test_confirmTransaction_incrementsCounterAndEmitsEvent() public {
        uint256 txId = _submitDummyTx();

        vm.expectEmit(true, true, false, false);
        emit TransactionConfirmed(txId, ANVIL_OWNER_2);

        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);

        (, , , , uint256 confirmations) = multiSigWallet.getTransaction(txId);
        assertEq(confirmations, 1);
        assertTrue(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));
    }

    function test_confirmTransaction_revert_callerIsNotOwner() public {
        uint256 txId = _submitDummyTx();
        vm.expectRevert(MultiSig__NotOwner.selector);
        vm.prank(nonOwner);
        multiSigWallet.confirmTransaction(txId);
    }

    function test_confirmTransaction_revert_txDoesNotExist() public {
        vm.expectRevert(MultiSig__TxDoesNotExist.selector);
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.confirmTransaction(NONEXISTENT_TX_ID);
    }

    function test_confirmTransaction_revert_txAlreadyExecuted() public {
        uint256 txId = _submitAndReachQuorum();
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);

        vm.expectRevert(MultiSig__TxAlreadyExecuted.selector);
        vm.prank(ANVIL_OWNER_3);
        multiSigWallet.confirmTransaction(txId);
    }

    function test_confirmTransaction_revert_ownerAlreadyConfirmed() public {
        uint256 txId = _submitDummyTx();
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);

        vm.expectRevert(MultiSig__TxAlreadyConfirmed.selector);
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);
    }

    // =========================================================================
    //  executeTransaction
    // =========================================================================

    function test_executeTransaction_callsTargetUpdatesStateEmitsEvent()
        public
    {
        bytes memory data = abi.encodeWithSelector(
            CallTarget.increment.selector
        );
        vm.prank(ANVIL_OWNER_1);
        uint256 txId = multiSigWallet.submitTransaction(
            address(callTarget),
            0,
            data
        );
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.confirmTransaction(txId);
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);

        vm.expectEmit(true, true, false, false);
        emit TransactionExecuted(txId, ANVIL_OWNER_1);

        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);

        (, , , bool executed, ) = multiSigWallet.getTransaction(txId);
        assertTrue(executed);
        assertEq(callTarget.count(), 1);
    }

    function test_executeTransaction_forwardsEthToTarget() public {
        vm.deal(address(multiSigWallet), ETH_SEND_AMOUNT);
        uint256 balanceBefore = user1.balance;

        vm.prank(ANVIL_OWNER_1);
        uint256 txId = multiSigWallet.submitTransaction(
            user1,
            ETH_SEND_AMOUNT,
            ""
        );
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.confirmTransaction(txId);
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);

        assertEq(user1.balance, balanceBefore + ETH_SEND_AMOUNT);
    }

    function test_executeTransaction_revert_callerIsNotOwner() public {
        uint256 txId = _submitAndReachQuorum();
        vm.expectRevert(MultiSig__NotOwner.selector);
        vm.prank(nonOwner);
        multiSigWallet.executeTransaction(txId);
    }

    function test_executeTransaction_revert_txDoesNotExist() public {
        vm.expectRevert(MultiSig__TxDoesNotExist.selector);
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(NONEXISTENT_TX_ID);
    }

    function test_executeTransaction_revert_txAlreadyExecuted() public {
        uint256 txId = _submitAndReachQuorum();
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);

        vm.expectRevert(MultiSig__TxAlreadyExecuted.selector);
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);
    }

    function test_executeTransaction_revert_confirmationsNotMet() public {
        uint256 txId = _submitDummyTx(); // 0 confirmations, needs REQUIRED
        vm.expectRevert(MultiSig__ConfirmationsNotMet.selector);
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);
    }

    function test_executeTransaction_revert_targetCallReverts() public {
        vm.prank(ANVIL_OWNER_1);
        uint256 txId = multiSigWallet.submitTransaction(
            address(revertingTarget),
            0,
            ""
        );
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.confirmTransaction(txId);
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);

        vm.expectRevert(MultiSig__TxFailed.selector);
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);
    }

    // =========================================================================
    //  revokeConfirmation
    // =========================================================================

    function test_revokeConfirmation_decrementsCounterAndEmitsEvent() public {
        uint256 txId = _submitDummyTx();
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);

        vm.expectEmit(true, true, false, false);
        emit ConfirmationRevoked(txId, ANVIL_OWNER_2);

        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.revokeConfirmation(txId);

        (, , , , uint256 confirmations) = multiSigWallet.getTransaction(txId);
        assertEq(confirmations, 0);
        assertFalse(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));
    }

    function test_revokeConfirmation_revert_callerIsNotOwner() public {
        uint256 txId = _submitDummyTx();
        vm.expectRevert(MultiSig__NotOwner.selector);
        vm.prank(nonOwner);
        multiSigWallet.revokeConfirmation(txId);
    }

    function test_revokeConfirmation_revert_txDoesNotExist() public {
        vm.expectRevert(MultiSig__TxDoesNotExist.selector);
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.revokeConfirmation(NONEXISTENT_TX_ID);
    }

    function test_revokeConfirmation_revert_txAlreadyExecuted() public {
        uint256 txId = _submitAndReachQuorum();
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);

        vm.expectRevert(MultiSig__TxAlreadyExecuted.selector);
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.revokeConfirmation(txId);
    }

    function test_revokeConfirmation_revert_ownerHasNotConfirmed() public {
        uint256 txId = _submitDummyTx();
        // ANVIL_OWNER_2 has not confirmed yet
        vm.expectRevert(MultiSig__TxNotConfirmed.selector);
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.revokeConfirmation(txId);
    }

    // =========================================================================
    //  confirmTransactionWithSig
    // =========================================================================

    function test_confirmTransactionWithSig_updatesStateIncrementsNonceEmitsEvent()
        public
    {
        uint256 txId = _submitDummyTx();
        uint256 nonceBefore = multiSigWallet.getNonce(ANVIL_OWNER_2);

        bytes memory sig = _signConfirm(ANVIL_OWNER_2_PK, ANVIL_OWNER_2, txId);

        vm.expectEmit(true, true, false, false);
        emit TransactionConfirmed(txId, ANVIL_OWNER_2);

        // Relayed by a third party — not an owner themselves
        vm.prank(nonOwner);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig);

        (, , , , uint256 confirmations) = multiSigWallet.getTransaction(txId);
        assertEq(confirmations, 1);
        assertTrue(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));
        assertEq(multiSigWallet.getNonce(ANVIL_OWNER_2), nonceBefore + 1);
    }

    function test_confirmTransactionWithSig_revert_txDoesNotExist() public {
        bytes memory sig = _signConfirm(
            ANVIL_OWNER_2_PK,
            ANVIL_OWNER_2,
            NONEXISTENT_TX_ID
        );
        vm.expectRevert(MultiSig__TxDoesNotExist.selector);
        multiSigWallet.confirmTransactionWithSig(
            NONEXISTENT_TX_ID,
            ANVIL_OWNER_2,
            sig
        );
    }

    function test_confirmTransactionWithSig_revert_txAlreadyExecuted() public {
        uint256 txId = _submitAndReachQuorum();
        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);

        bytes memory sig = _signConfirm(ANVIL_OWNER_3_PK, ANVIL_OWNER_3, txId);
        vm.expectRevert(MultiSig__TxAlreadyExecuted.selector);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_3, sig);
    }

    function test_confirmTransactionWithSig_revert_signerIsNotOwner() public {
        uint256 txId = _submitDummyTx();
        bytes memory sig = _signConfirm(NON_OWNER_PK, nonOwner, txId);
        vm.expectRevert(MultiSig__NotOwner.selector);
        multiSigWallet.confirmTransactionWithSig(txId, nonOwner, sig);
    }

    function test_confirmTransactionWithSig_revert_signerAlreadyConfirmed()
        public
    {
        uint256 txId = _submitDummyTx();

        // First confirmation via sig — succeeds
        bytes memory sig1 = _signConfirm(ANVIL_OWNER_2_PK, ANVIL_OWNER_2, txId);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig1);

        // Second attempt — owner2 is already confirmed; nonce now stale but
        // the AlreadyConfirmed check fires before the sig check anyway
        bytes memory sig2 = _signConfirm(ANVIL_OWNER_2_PK, ANVIL_OWNER_2, txId);
        vm.expectRevert(MultiSig__TxAlreadyConfirmed.selector);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig2);
    }

    function test_confirmTransactionWithSig_revert_wrongSignerProducesInvalidSig()
        public
    {
        uint256 txId = _submitDummyTx();
        // Sign with a non-owner's key, but claim it is owner2
        bytes memory wrongSig = _signConfirm(NON_OWNER_PK, ANVIL_OWNER_2, txId);
        vm.expectRevert(MultiSig__InvalidSignature.selector);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, wrongSig);
    }

    function test_confirmTransactionWithSig_revert_replayAttackWithStaleNonce()
        public
    {
        // sig0 is bound to txId=0 AND nonce=0
        uint256 txId0 = _submitDummyTx();
        bytes memory sig0 = _signConfirm(
            ANVIL_OWNER_2_PK,
            ANVIL_OWNER_2,
            txId0
        );

        // Consume the sig → nonce advances from 0 to 1
        multiSigWallet.confirmTransactionWithSig(txId0, ANVIL_OWNER_2, sig0);
        assertEq(multiSigWallet.getNonce(ANVIL_OWNER_2), 1);

        // Owner2 has NOT confirmed txId1 yet
        uint256 txId1 = _submitDummyTx();

        // Replaying sig0 (nonce=0) for txId1 is invalid because current nonce=1
        vm.expectRevert(MultiSig__InvalidSignature.selector);
        multiSigWallet.confirmTransactionWithSig(txId1, ANVIL_OWNER_2, sig0);
    }

    // =========================================================================
    //  getConfirmDigest
    // =========================================================================

    function test_getConfirmDigest_signingItRecoversSigner() public view {
        // We cannot submit a tx in a view context; tx 0 need not exist for
        // digest computation — it only depends on txId + address + nonce.
        uint256 txId = 0;
        bytes32 digest = multiSigWallet.getConfirmDigest(txId, ANVIL_OWNER_1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ANVIL_OWNER_1_PK, digest);
        address recovered = ecrecover(digest, v, r, s);
        assertEq(recovered, ANVIL_OWNER_1);
    }

    function test_getConfirmDigest_changesWith_nonce() public {
        uint256 txId = _submitDummyTx();
        bytes32 digestAtNonce0 = multiSigWallet.getConfirmDigest(
            txId,
            ANVIL_OWNER_2
        );

        // Consume nonce by confirming with a valid sig
        bytes memory sig = _signConfirm(ANVIL_OWNER_2_PK, ANVIL_OWNER_2, txId);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig);

        bytes32 digestAtNonce1 = multiSigWallet.getConfirmDigest(
            txId,
            ANVIL_OWNER_2
        );
        assertTrue(digestAtNonce0 != digestAtNonce1);
    }

    // =========================================================================
    //  receive
    // =========================================================================

    function test_receive_acceptsEthAndUpdatesBalance() public {
        uint256 balanceBefore = address(multiSigWallet).balance;
        vm.deal(user1, ETH_RECEIVE_AMOUNT);

        vm.prank(user1);
        (bool ok, ) = address(multiSigWallet).call{value: ETH_RECEIVE_AMOUNT}(
            ""
        );

        assertTrue(ok);
        assertEq(
            address(multiSigWallet).balance,
            balanceBefore + ETH_RECEIVE_AMOUNT
        );
    }

    // =========================================================================
    //  Getters
    // =========================================================================

    function test_getTransactionCount_incrementsOnEverySubmit() public {
        uint256 countBefore = multiSigWallet.getTransactionCount();
        _submitDummyTx();
        assertEq(multiSigWallet.getTransactionCount(), countBefore + 1);
        _submitDummyTx();
        assertEq(multiSigWallet.getTransactionCount(), countBefore + 2);
    }

    function test_getOwners_returnsFullOwnersArray() public view {
        address[] memory owners = multiSigWallet.getOwners();
        assertEq(owners.length, EXPECTED_OWNER_COUNT);
        assertEq(owners[OWNER_INDEX_0], ANVIL_OWNER_1);
        assertEq(owners[OWNER_INDEX_1], ANVIL_OWNER_2);
        assertEq(owners[OWNER_INDEX_2], ANVIL_OWNER_3);
    }

    function test_isOwner_returnsTrueForOwnersAndFalseOtherwise() public view {
        assertTrue(multiSigWallet.isOwner(ANVIL_OWNER_1));
        assertTrue(multiSigWallet.isOwner(ANVIL_OWNER_2));
        assertTrue(multiSigWallet.isOwner(ANVIL_OWNER_3));
        assertFalse(multiSigWallet.isOwner(nonOwner));
    }

    function test_getRequiredConfirmations_matchesDeployedValue() public view {
        assertEq(
            multiSigWallet.getRequiredConfirmations(),
            MULTISIG_REQUIRED_CONFIRMATIONS
        );
    }

    function test_getOwnerAt_returnsCorrectAddressForEachIndex() public view {
        assertEq(multiSigWallet.getOwnerAt(OWNER_INDEX_0), ANVIL_OWNER_1);
        assertEq(multiSigWallet.getOwnerAt(OWNER_INDEX_1), ANVIL_OWNER_2);
        assertEq(multiSigWallet.getOwnerAt(OWNER_INDEX_2), ANVIL_OWNER_3);
    }

    function test_getNonce_startsAtZeroAndIncrementsAfterSigConfirm() public {
        assertEq(multiSigWallet.getNonce(ANVIL_OWNER_1), 0);

        uint256 txId = _submitDummyTx();
        bytes memory sig = _signConfirm(ANVIL_OWNER_1_PK, ANVIL_OWNER_1, txId);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_1, sig);

        assertEq(multiSigWallet.getNonce(ANVIL_OWNER_1), 1);
    }

    function test_isTransactionConfirmed_reflectsConfirmAndRevoke() public {
        uint256 txId = _submitDummyTx();

        assertFalse(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));

        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);
        assertTrue(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));

        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.revokeConfirmation(txId);
        assertFalse(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));
    }
}
