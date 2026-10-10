// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {CodeConstants} from "../../script/CodeConstants.sol";
import {MultiSigWallet} from "../../src/MultiSigWallet.sol";

import "../../src/errors/MultiSigWalletErrors.sol";

/// @dev Call target whose `increment` lets tests build a realistic calldata payload.
contract ConfirmSigCallTarget {
    uint256 public count;

    function increment() external {
        count++;
    }

    receive() external payable {}
}

/**
 * @dev L-06: EIP-712 confirmation signatures are bound to the stored tx content
 *      (txId, target, value, keccak256(data)) under domain ("MultiSigWallet", "2") and to a
 *      per-(txId, owner) nonce, bumped when a signature is consumed and on revokeConfirmation.
 *      Digests are rebuilt test-side from the typehash so the tests do not trust getConfirmDigest.
 */
contract MultiSigWalletConfirmWithSigTest is BaseTest, CodeConstants {
    // Well-known private keys for Anvil accounts 1, 2, 3 (owners of the deployed wallet)
    uint256 constant ANVIL_OWNER_1_PK =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant ANVIL_OWNER_2_PK =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant ANVIL_OWNER_3_PK =
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    // =========================================================================
    //  EIP-712 constants (mirror the contract, built independently)
    // =========================================================================

    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 constant CONFIRM_TYPEHASH =
        keccak256(
            "Confirm(uint256 txId,address target,uint256 value,bytes32 dataHash,uint256 nonce)"
        );
    string constant DOMAIN_NAME = "MultiSigWallet";
    string constant DOMAIN_VERSION = "2";
    /// Version used before L-06: signatures under it must no longer verify
    string constant OLD_DOMAIN_VERSION = "1";

    /// Nonce of every (txId, owner) pair before any use / revoke
    uint256 constant INITIAL_NONCE = 0;
    uint256 constant ETH_VALUE = 1 ether;

    // =========================================================================
    //  State
    // =========================================================================

    ConfirmSigCallTarget callTarget;
    address attacker = makeAddr("attacker");
    address relayer = makeAddr("relayer");
    bytes s_incrementData;

    // =========================================================================
    //  setUp
    // =========================================================================

    function setUp() public override {
        super.setUp();
        callTarget = new ConfirmSigCallTarget();
        s_incrementData = abi.encodeWithSelector(
            ConfirmSigCallTarget.increment.selector
        );
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _domainSeparator(
        string memory _version,
        address _wallet
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN_TYPEHASH,
                    keccak256(bytes(DOMAIN_NAME)),
                    keccak256(bytes(_version)),
                    block.chainid,
                    _wallet
                )
            );
    }

    function _confirmDigest(
        bytes32 _domainSep,
        uint256 _txId,
        address _target,
        uint256 _value,
        bytes memory _data,
        uint256 _nonce
    ) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                CONFIRM_TYPEHASH,
                _txId,
                _target,
                _value,
                keccak256(_data),
                _nonce
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", _domainSep, structHash));
    }

    /// @dev Off-chain style digest for the deployed wallet (domain version "2").
    function _walletDigest(
        uint256 _txId,
        address _target,
        uint256 _value,
        bytes memory _data,
        uint256 _nonce
    ) internal view returns (bytes32) {
        return
            _confirmDigest(
                _domainSeparator(DOMAIN_VERSION, address(multiSigWallet)),
                _txId,
                _target,
                _value,
                _data,
                _nonce
            );
    }

    function _sign(
        uint256 _pk,
        bytes32 _digest
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, _digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Owner-2 signature over the increment tx at `_txId` with `_nonce`, built off-chain.
    function _signIncrementTx(
        uint256 _txId,
        uint256 _nonce
    ) internal view returns (bytes memory) {
        return
            _sign(
                ANVIL_OWNER_2_PK,
                _walletDigest(
                    _txId,
                    address(callTarget),
                    0,
                    s_incrementData,
                    _nonce
                )
            );
    }

    function _submitIncrementTx() internal returns (uint256 txId) {
        vm.prank(ANVIL_OWNER_1);
        txId = multiSigWallet.submitTransaction(
            address(callTarget),
            0,
            s_incrementData
        );
    }

    function _confirmations(uint256 _txId) internal view returns (uint256 c) {
        (, , , , c) = multiSigWallet.getTransaction(_txId);
    }

    // =========================================================================
    //  getConfirmDigest / domain
    // =========================================================================

    function test_getConfirmDigest_matchesTestSideEip712Digest() public {
        uint256 txId = _submitIncrementTx();

        bytes32 expected = _walletDigest(
            txId,
            address(callTarget),
            0,
            s_incrementData,
            INITIAL_NONCE
        );

        assertEq(
            multiSigWallet.getConfirmDigest(txId, ANVIL_OWNER_2),
            expected,
            "on-chain digest must match the typehash + domain v2 digest"
        );
    }

    function test_getConfirmDigest_bindsValueAndTarget() public {
        vm.prank(ANVIL_OWNER_1);
        uint256 txId = multiSigWallet.submitTransaction(
            attacker,
            ETH_VALUE,
            ""
        );

        assertEq(
            multiSigWallet.getConfirmDigest(txId, ANVIL_OWNER_3),
            _walletDigest(txId, attacker, ETH_VALUE, "", INITIAL_NONCE),
            "digest must encode the stored target, value and empty-data hash"
        );
    }

    function test_getConfirmDigest_tracksPerTxNonceAfterUse() public {
        uint256 txId = _submitIncrementTx();
        multiSigWallet.confirmTransactionWithSig(
            txId,
            ANVIL_OWNER_2,
            _signIncrementTx(txId, INITIAL_NONCE)
        );

        assertEq(
            multiSigWallet.getConfirmDigest(txId, ANVIL_OWNER_2),
            _walletDigest(
                txId,
                address(callTarget),
                0,
                s_incrementData,
                INITIAL_NONCE + 1
            ),
            "digest must use the bumped nonce"
        );
    }

    function test_getConfirmDigest_revert_txDoesNotExist() public {
        uint256 unknownTxId = multiSigWallet.getTransactionCount();

        vm.expectRevert(MultiSig__TxDoesNotExist.selector);
        multiSigWallet.getConfirmDigest(unknownTxId, ANVIL_OWNER_2);
    }

    function test_eip712Domain_reportsNameVersion2ChainIdAndWallet()
        public
        view
    {
        (
            ,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            ,

        ) = multiSigWallet.eip712Domain();

        assertEq(name, DOMAIN_NAME);
        assertEq(version, DOMAIN_VERSION);
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(multiSigWallet));
    }

    // =========================================================================
    //  getConfirmNonce
    // =========================================================================

    function test_getConfirmNonce_isZeroForUnknownTxId() public view {
        uint256 unknownTxId = multiSigWallet.getTransactionCount();
        assertEq(
            multiSigWallet.getConfirmNonce(unknownTxId, ANVIL_OWNER_2),
            INITIAL_NONCE
        );
    }

    function test_getConfirmNonce_isIndependentPerTxIdAndOwner() public {
        uint256 txA = _submitIncrementTx();
        uint256 txB = _submitIncrementTx();

        multiSigWallet.confirmTransactionWithSig(
            txA,
            ANVIL_OWNER_2,
            _signIncrementTx(txA, INITIAL_NONCE)
        );

        assertEq(
            multiSigWallet.getConfirmNonce(txA, ANVIL_OWNER_2),
            INITIAL_NONCE + 1,
            "used (txA, owner2) nonce must be bumped"
        );
        assertEq(
            multiSigWallet.getConfirmNonce(txB, ANVIL_OWNER_2),
            INITIAL_NONCE,
            "(txB, owner2) nonce must be untouched"
        );
        assertEq(
            multiSigWallet.getConfirmNonce(txA, ANVIL_OWNER_3),
            INITIAL_NONCE,
            "(txA, owner3) nonce must be untouched"
        );
    }

    function test_getConfirmNonce_incrementsOnRevokeConfirmation() public {
        uint256 txId = _submitIncrementTx();
        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);
        assertEq(
            multiSigWallet.getConfirmNonce(txId, ANVIL_OWNER_2),
            INITIAL_NONCE,
            "direct confirm must not touch the nonce"
        );

        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.revokeConfirmation(txId);

        assertEq(
            multiSigWallet.getConfirmNonce(txId, ANVIL_OWNER_2),
            INITIAL_NONCE + 1,
            "revoke must bump the caller nonce for that txId"
        );
        assertEq(
            multiSigWallet.getConfirmNonce(txId, ANVIL_OWNER_3),
            INITIAL_NONCE,
            "other owners' nonce must be untouched"
        );
    }

    // =========================================================================
    //  Binding to tx content
    // =========================================================================

    function test_confirmTransactionWithSig_revert_preSignedSigOnDifferentTxAtSameId()
        public
    {
        // Owner2 signs off-chain the tx expected at the next id, before it is submitted.
        uint256 expectedTxId = multiSigWallet.getTransactionCount();
        bytes memory preSigned = _signIncrementTx(expectedTxId, INITIAL_NONCE);

        // A malicious owner front-runs and submits a different tx at that id.
        vm.prank(ANVIL_OWNER_1);
        uint256 txId = multiSigWallet.submitTransaction(
            attacker,
            ETH_VALUE,
            ""
        );
        assertEq(txId, expectedTxId, "fixture: tx must occupy the signed id");

        vm.expectRevert(MultiSig__InvalidSignature.selector);
        vm.prank(relayer);
        multiSigWallet.confirmTransactionWithSig(
            txId,
            ANVIL_OWNER_2,
            preSigned
        );
    }

    function test_confirmTransactionWithSig_revert_preSignedSigOnSameTargetDifferentData()
        public
    {
        uint256 expectedTxId = multiSigWallet.getTransactionCount();
        bytes memory preSigned = _signIncrementTx(expectedTxId, INITIAL_NONCE);

        // Same target and value, only the calldata differs.
        vm.prank(ANVIL_OWNER_1);
        uint256 txId = multiSigWallet.submitTransaction(
            address(callTarget),
            0,
            ""
        );

        vm.expectRevert(MultiSig__InvalidSignature.selector);
        multiSigWallet.confirmTransactionWithSig(
            txId,
            ANVIL_OWNER_2,
            preSigned
        );
    }

    function test_confirmTransactionWithSig_revert_preSignedSigOnSameCallDifferentValue()
        public
    {
        uint256 expectedTxId = multiSigWallet.getTransactionCount();
        bytes memory preSigned = _signIncrementTx(expectedTxId, INITIAL_NONCE);

        // Same target and calldata, only the ETH value differs.
        vm.prank(ANVIL_OWNER_1);
        uint256 txId = multiSigWallet.submitTransaction(
            address(callTarget),
            ETH_VALUE,
            s_incrementData
        );

        vm.expectRevert(MultiSig__InvalidSignature.selector);
        multiSigWallet.confirmTransactionWithSig(
            txId,
            ANVIL_OWNER_2,
            preSigned
        );
    }

    function test_confirmTransactionWithSig_preSignedSigConfirmsMatchingTx()
        public
    {
        uint256 expectedTxId = multiSigWallet.getTransactionCount();
        bytes memory preSigned = _signIncrementTx(expectedTxId, INITIAL_NONCE);

        uint256 txId = _submitIncrementTx();
        assertEq(txId, expectedTxId);
        assertEq(_confirmations(txId), 0);
        assertFalse(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));

        vm.prank(relayer);
        multiSigWallet.confirmTransactionWithSig(
            txId,
            ANVIL_OWNER_2,
            preSigned
        );

        assertEq(_confirmations(txId), 1);
        assertTrue(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));
        assertEq(
            multiSigWallet.getConfirmNonce(txId, ANVIL_OWNER_2),
            INITIAL_NONCE + 1
        );
    }

    function test_confirmTransactionWithSig_revert_sigUnderOldDomainVersion()
        public
    {
        uint256 txId = _submitIncrementTx();
        bytes32 oldDigest = _confirmDigest(
            _domainSeparator(OLD_DOMAIN_VERSION, address(multiSigWallet)),
            txId,
            address(callTarget),
            0,
            s_incrementData,
            INITIAL_NONCE
        );

        vm.expectRevert(MultiSig__InvalidSignature.selector);
        multiSigWallet.confirmTransactionWithSig(
            txId,
            ANVIL_OWNER_2,
            _sign(ANVIL_OWNER_2_PK, oldDigest)
        );
    }

    function test_confirmTransactionWithSig_revert_sigForAnotherWallet()
        public
    {
        // Same owners, same tx content and id, different verifyingContract.
        MultiSigWallet otherWallet = new MultiSigWallet(
            multiSigWallet.getOwners(),
            multiSigWallet.getRequiredConfirmations()
        );
        // Align ids so only the domain differs: fill the other wallet up to the next id here.
        uint256 txId = multiSigWallet.getTransactionCount();
        uint256 otherTxId;
        do {
            vm.prank(ANVIL_OWNER_1);
            otherTxId = otherWallet.submitTransaction(
                address(callTarget),
                0,
                s_incrementData
            );
        } while (otherTxId < txId);
        assertEq(_submitIncrementTx(), otherTxId, "fixture: ids must match");

        bytes memory otherWalletSig = _sign(
            ANVIL_OWNER_2_PK,
            otherWallet.getConfirmDigest(otherTxId, ANVIL_OWNER_2)
        );

        vm.expectRevert(MultiSig__InvalidSignature.selector);
        multiSigWallet.confirmTransactionWithSig(
            txId,
            ANVIL_OWNER_2,
            otherWalletSig
        );
    }

    // =========================================================================
    //  Parallel signatures
    // =========================================================================

    function test_confirmTransactionWithSig_parallelSigsForTwoTxIdsAreBothUsable()
        public
    {
        uint256 txA = _submitIncrementTx();
        uint256 txB = _submitIncrementTx();

        // Both prepared before either is used (old global nonce: second would fail).
        bytes memory sigA = _signIncrementTx(txA, INITIAL_NONCE);
        bytes memory sigB = _signIncrementTx(txB, INITIAL_NONCE);

        multiSigWallet.confirmTransactionWithSig(txA, ANVIL_OWNER_2, sigA);
        multiSigWallet.confirmTransactionWithSig(txB, ANVIL_OWNER_2, sigB);

        assertTrue(multiSigWallet.isTransactionConfirmed(txA, ANVIL_OWNER_2));
        assertTrue(multiSigWallet.isTransactionConfirmed(txB, ANVIL_OWNER_2));
        assertEq(_confirmations(txA), 1);
        assertEq(_confirmations(txB), 1);
    }

    function test_confirmTransactionWithSig_parallelSigsUsableInReverseOrder()
        public
    {
        uint256 txA = _submitIncrementTx();
        uint256 txB = _submitIncrementTx();
        bytes memory sigA = _signIncrementTx(txA, INITIAL_NONCE);
        bytes memory sigB = _signIncrementTx(txB, INITIAL_NONCE);

        multiSigWallet.confirmTransactionWithSig(txB, ANVIL_OWNER_2, sigB);
        multiSigWallet.confirmTransactionWithSig(txA, ANVIL_OWNER_2, sigA);

        assertTrue(multiSigWallet.isTransactionConfirmed(txA, ANVIL_OWNER_2));
        assertTrue(multiSigWallet.isTransactionConfirmed(txB, ANVIL_OWNER_2));
    }

    function test_confirmTransactionWithSig_preSignedSigsReachQuorumAndExecute()
        public
    {
        uint256 txId = _submitIncrementTx();
        bytes memory sig2 = _signIncrementTx(txId, INITIAL_NONCE);
        bytes memory sig3 = _sign(
            ANVIL_OWNER_3_PK,
            _walletDigest(
                txId,
                address(callTarget),
                0,
                s_incrementData,
                INITIAL_NONCE
            )
        );

        vm.startPrank(relayer);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig2);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_3, sig3);
        vm.stopPrank();

        vm.prank(ANVIL_OWNER_1);
        multiSigWallet.executeTransaction(txId);

        (, , , bool executed, ) = multiSigWallet.getTransaction(txId);
        assertTrue(executed);
        assertEq(callTarget.count(), 1);
    }

    // =========================================================================
    //  Replay & revoke
    // =========================================================================

    function test_confirmTransactionWithSig_revert_replayWhileStillConfirmed()
        public
    {
        uint256 txId = _submitIncrementTx();
        bytes memory sig = _signIncrementTx(txId, INITIAL_NONCE);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig);

        vm.expectRevert(MultiSig__TxAlreadyConfirmed.selector);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig);
    }

    function test_confirmTransactionWithSig_revert_replayOfUsedSigAfterRevoke()
        public
    {
        uint256 txId = _submitIncrementTx();
        bytes memory sig = _signIncrementTx(txId, INITIAL_NONCE);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig);

        vm.prank(ANVIL_OWNER_2);
        multiSigWallet.revokeConfirmation(txId);

        vm.expectRevert(MultiSig__InvalidSignature.selector);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, sig);
    }

    function test_confirmTransactionWithSig_revert_sigCollectedBeforeRevokeCannotReconfirm()
        public
    {
        uint256 txId = _submitIncrementTx();
        // Signature collected by a relayer but never submitted.
        bytes memory staleSig = _signIncrementTx(txId, INITIAL_NONCE);

        // Owner confirms directly, then changes their mind.
        vm.startPrank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);
        multiSigWallet.revokeConfirmation(txId);
        vm.stopPrank();

        vm.expectRevert(MultiSig__InvalidSignature.selector);
        vm.prank(relayer);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, staleSig);
    }

    function test_confirmTransactionWithSig_freshSigAfterRevokeConfirms()
        public
    {
        uint256 txId = _submitIncrementTx();
        vm.startPrank(ANVIL_OWNER_2);
        multiSigWallet.confirmTransaction(txId);
        multiSigWallet.revokeConfirmation(txId);
        vm.stopPrank();

        uint256 currentNonce = multiSigWallet.getConfirmNonce(
            txId,
            ANVIL_OWNER_2
        );
        assertEq(currentNonce, INITIAL_NONCE + 1);
        assertEq(_confirmations(txId), 0);

        bytes memory freshSig = _signIncrementTx(txId, currentNonce);
        vm.prank(relayer);
        multiSigWallet.confirmTransactionWithSig(txId, ANVIL_OWNER_2, freshSig);

        assertTrue(multiSigWallet.isTransactionConfirmed(txId, ANVIL_OWNER_2));
        assertEq(_confirmations(txId), 1);
        assertEq(
            multiSigWallet.getConfirmNonce(txId, ANVIL_OWNER_2),
            currentNonce + 1
        );
    }
}
