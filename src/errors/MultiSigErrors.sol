//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error MultiSig__NotOwner();
error MultiSig__TxDoesNotExist();
error MultiSig__TxAlreadyExecuted();
error MultiSig__TxAlreadyConfirmed();
error MultiSig__TxNotConfirmed();
error MultiSig__ConfirmationsNotMet();
error MultiSig__TxFailed();
error MultiSig__InvalidRequirement();
error MultiSig__OwnerNotUnique();
error MultiSig__ZeroAddress();
