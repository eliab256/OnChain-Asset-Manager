//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Mock ERC20 token for testing.
 *
 * In ERC20 there is no internal scaling: `decimals()` is pure metadata.
 * All balances are stored in raw smallest-unit amounts, so:
 *   - if decimals = 6  → mint(1_000_000)  = "1 token"  (like USDC)
 *   - if decimals = 18 → mint(1e18)       = "1 token"  (like WETH)
 *
 * Any contract that reads `IERC20Metadata.decimals()` (e.g. Index.sol) will
 * automatically use the correct value for its math, because this mock
 * overrides it — so the full accounting chain is affected.
 *
 * Helpers:
 *   - `mintHumanAmount(to, humanAmount)` scales by 10**decimals automatically.
 *   - `setDecimals(newDecimals)`         lets you change decimals after deploy
 *                                        to test edge-cases without redeploying.
 */
contract AssetTokenMock is ERC20 {
    uint8 private s_decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        s_decimals = decimals_;
    }

    // ─── Overrides ────────────────────────────────────────────────────────────

    function decimals() public view override returns (uint8) {
        return s_decimals;
    }

    // ─── Mint helpers ─────────────────────────────────────────────────────────

    /// @notice Mint raw smallest-unit amount (same as a real ERC20 transfer/mint).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Mint a "human-readable" amount: 1 → 1 * 10**decimals.
    /// @dev    Useful to avoid hardcoding `1e6` vs `1e18` in tests.
    function mintHumanAmount(address to, uint256 humanAmount) external {
        _mint(to, humanAmount * 10 ** s_decimals);
    }

    // ─── Test utilities ───────────────────────────────────────────────────────

    /// @notice Change decimals after deployment to test edge-cases.
    /// @dev    WARNING: changing decimals of a token that already has balances
    ///         reinterprets existing raw amounts — use only in controlled tests.
    function setDecimals(uint8 newDecimals) external {
        s_decimals = newDecimals;
    }
}
