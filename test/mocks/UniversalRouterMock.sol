// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockUniversalRouter
 * @notice Simulates Uniswap's UniversalRouter for unit tests.
 *
 * @dev Supports both V3 (command 0x00) and V4 (command 0x10) swap formats,
 *      mirroring the exact encoding produced by SwapManager.sol.
 *
 * ── Exchange rate model ────────────────────────────────────────────────────
 *
 *   amountOut = (amountIn * rate) / RATE_PRECISION   (RATE_PRECISION = 1e18)
 *
 *   Example: USDC (6 dec) → WETH (18 dec) at $2 000 / ETH
 *
 *     1 USDC  = 1e6  raw units in
 *     0.0005 WETH = 5e14 raw units out
 *
 *     rate = (5e14 * 1e18) / 1e6  =  5e26
 *
 *   Helper (pure):  computeRate(amountIn, amountOut)  does this for you.
 *
 * ── Funding ────────────────────────────────────────────────────────────────
 *
 *   The mock must hold the output tokens before any swap is executed.
 *   Call  fundToken(token, amount)  from your test (after minting/transferring
 *   tokens to this contract) to pre-load liquidity.
 *
 * ── Approval requirement ───────────────────────────────────────────────────
 *
 *   The mock uses safeTransferFrom to pull input tokens, so the caller
 *   (the Index contract) MUST have approved this mock for tokenIn before
 *   calling execute(). Index.sol does this correctly for:
 *     - USDC → Asset swaps  (_swapUsdcForAssets, forceApprove before execute)
 *     - Asset → Asset swaps (_swapAssetForAsset, forceApprove before execute)
 *   NOTE: _swapAssetsForUsdc in Index.sol currently lacks a forceApprove —
 *   that is a known issue in the source; tests for that flow should add an
 *   explicit approval via vm.prank + IERC20.approve in the test setup.
 */
contract UniversalRouterMock {
    using SafeERC20 for IERC20;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error UniversalRouterMock__RateNotSet(address tokenIn, address tokenOut);
    error UniversalRouterMock__InsufficientOutputBalance(address token, uint256 needed, uint256 available);
    error UniversalRouterMock__UnsupportedCommand(uint8 command);
    error UniversalRouterMock__InvalidPath();

    // ─── Constants ────────────────────────────────────────────────────────────

    uint8 public constant V3_SWAP_EXACT_IN = 0x00;
    uint8 public constant V4_SWAP = 0x10;
    uint256 public constant RATE_PRECISION = 1e18;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice exchangeRates[tokenIn][tokenOut] = rate (scaled by RATE_PRECISION).
    mapping(address => mapping(address => uint256)) public exchangeRates;

    // ─── Events ───────────────────────────────────────────────────────────────

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    event RateSet(address indexed tokenIn, address indexed tokenOut, uint256 rate);

    // ─── Configuration ────────────────────────────────────────────────────────

    /**
     * @notice Sets the exchange rate for a token pair.
     * @param tokenIn  Address of the input token.
     * @param tokenOut Address of the output token.
     * @param rate     amountOut = (amountIn * rate) / RATE_PRECISION.
     *                 Use computeRate() to derive this value from human amounts.
     */
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        exchangeRates[tokenIn][tokenOut] = rate;
        emit RateSet(tokenIn, tokenOut, rate);
    }

    /**
     * @notice Sets rates for both directions of a pair in one call.
     * @param tokenA    First token.
     * @param tokenB    Second token.
     * @param rateAToB  Rate for tokenA → tokenB.
     * @param rateBToA  Rate for tokenB → tokenA.
     */
    function setExchangeRateBidirectional(
        address tokenA,
        address tokenB,
        uint256 rateAToB,
        uint256 rateBToA
    ) external {
        exchangeRates[tokenA][tokenB] = rateAToB;
        exchangeRates[tokenB][tokenA] = rateBToA;
        emit RateSet(tokenA, tokenB, rateAToB);
        emit RateSet(tokenB, tokenA, rateBToA);
    }

    /**
     * @notice Transfers tokens into this contract so it can pay out swaps.
     * @dev    Call this from your test after minting tokens to address(this),
     *         or simply mint directly to address(this).
     */
    function fundToken(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    // ─── Core execute ─────────────────────────────────────────────────────────

    /**
     * @notice Mirrors IUniversalRouter.execute(commands, inputs, deadline).
     * @dev    Iterates over each command byte and dispatches to the correct handler.
     *         The `deadline` parameter is accepted but not enforced (use vm.warp in tests).
     */
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 /* deadline */
    ) external {
        uint256 numCommands = commands.length;
        for (uint256 i = 0; i < numCommands; i++) {
            uint8 command = uint8(commands[i]);
            if (command == V3_SWAP_EXACT_IN) {
                _handleV3Swap(inputs[i]);
            } else if (command == V4_SWAP) {
                _handleV4Swap(inputs[i]);
            } else {
                revert UniversalRouterMock__UnsupportedCommand(command);
            }
        }
    }

    // ─── V3 handler ───────────────────────────────────────────────────────────

    /**
     * @dev Decodes a V3_SWAP_EXACT_IN input and executes the simulated swap.
     *
     *      Input encoding (matches SwapManager._buildV3Params):
     *        abi.encode(address recipient, uint256 amountIn, uint256 amountOutMin,
     *                   bytes path, bool payerIsUser)
     *
     *      Path encoding: abi.encodePacked(tokenIn[20], fee[3], tokenOut[20] [, fee[3], tokenMid[20], ...])
     */
    function _handleV3Swap(bytes calldata input) internal {
        (
            address recipient,
            uint256 amountIn,
            ,          // amountOutMin — ignored in mock
            bytes memory path,
            // payerIsUser — ignored in mock (we always pull from msg.sender)
        ) = abi.decode(input, (address, uint256, uint256, bytes, bool));

        if (path.length < 43) revert UniversalRouterMock__InvalidPath();

        address tokenIn  = _addressAt(path, 0);
        address tokenOut = _addressAt(path, path.length - 20);

        _executeSwap(tokenIn, tokenOut, amountIn, recipient);
    }

    // ─── V4 handler ───────────────────────────────────────────────────────────

    /**
     * @dev Decodes a V4_SWAP input and executes the simulated swap.
     *
     *      Input encoding (matches SwapManager._buildV4Params):
     *        abi.encode(bytes actions, bytes[] actionParams)
     *
     *      actionParams[0] = abi.encode(ExactInputSingleParams) — not read
     *      actionParams[1] = abi.encode(Currency tokenIn,  uint256 amountIn)   // SETTLE_ALL
     *      actionParams[2] = abi.encode(Currency tokenOut, uint256 minOut)     // TAKE_ALL
     *
     *      Currency is address-wrapped, so it decodes cleanly as address.
     *      For V4 the output goes back to msg.sender (the Index contract),
     *      mirroring the TAKE_ALL action behaviour.
     */
    function _handleV4Swap(bytes calldata input) internal {
        (, bytes[] memory actionParams) = abi.decode(input, (bytes, bytes[]));

        (address tokenIn,  uint256 amountIn) = abi.decode(actionParams[1], (address, uint256));
        (address tokenOut, )                 = abi.decode(actionParams[2], (address, uint256));

        // V4 TAKE_ALL sends output to the caller (the Index contract).
        _executeSwap(tokenIn, tokenOut, amountIn, msg.sender);
    }

    // ─── Internal swap logic ──────────────────────────────────────────────────

    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) internal {
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) revert UniversalRouterMock__RateNotSet(tokenIn, tokenOut);

        uint256 amountOut = (amountIn * rate) / RATE_PRECISION;

        // Verify the mock has enough output tokens.
        uint256 available = IERC20(tokenOut).balanceOf(address(this));
        if (available < amountOut) {
            revert UniversalRouterMock__InsufficientOutputBalance(tokenOut, amountOut, available);
        }

        // Pull input tokens from the caller.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Send output tokens to the recipient.
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

    // ─── Path helpers ─────────────────────────────────────────────────────────

    /// @dev Reads a 20-byte address from `data` starting at byte `offset`.
    function _addressAt(bytes memory data, uint256 offset) internal pure returns (address result) {
        // Load 32 bytes at offset and right-align the address (shift left 96 bits = 12 bytes).
        assembly {
            result := shr(96, mload(add(add(data, 0x20), offset)))
        }
    }

    // ─── Pure helpers for test setup ─────────────────────────────────────────

    /**
     * @notice Derives the rate value from concrete raw token amounts.
     * @dev    Use this in test setUp to avoid manual 1e18-scaled arithmetic.
     *
     *         Example — USDC (6 dec) → WETH (18 dec) @ $2 000:
     *           computeRate(1e6, 5e14)  →  5e26
     *
     * @param amountIn  Raw input amount (in tokenIn's decimals).
     * @param amountOut Raw output amount (in tokenOut's decimals).
     * @return rate     Value to pass to setExchangeRate().
     */
    function computeRate(uint256 amountIn, uint256 amountOut) external pure returns (uint256 rate) {
        rate = (amountOut * RATE_PRECISION) / amountIn;
    }

    /**
     * @notice Previews the amountOut the mock would return for a given amountIn.
     * @param tokenIn  Input token address.
     * @param tokenOut Output token address.
     * @param amountIn Raw input amount.
     * @return amountOut Expected raw output amount.
     */
    function previewSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) revert UniversalRouterMock__RateNotSet(tokenIn, tokenOut);
        amountOut = (amountIn * rate) / RATE_PRECISION;
    }
}
