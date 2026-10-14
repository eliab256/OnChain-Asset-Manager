// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Raised when the data contract runtime (STOP byte + data) would exceed the EIP-170 limit.
error SplitCode__DataTooLarge(uint256 runtimeSize);
error SplitCode__DeployFailed();
