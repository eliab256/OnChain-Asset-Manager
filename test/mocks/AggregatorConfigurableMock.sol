// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Chainlink AggregatorV3 mock whose round data, decimals and failure modes are fully settable.
 *      MockV3Aggregator always returns answeredInRound == roundId and cannot revert, so it cannot
 *      reproduce a stale round, a feed with more than 18 decimals or a deprecated (reverting) feed.
 */
contract AggregatorConfigurableMock {
    error AggregatorConfigurableMock__Reverted();

    uint8 private s_decimals;
    uint80 private s_roundId;
    int256 private s_answer;
    uint256 private s_startedAt;
    uint256 private s_updatedAt;
    uint80 private s_answeredInRound;
    bool private s_revertOnLatestRoundData;
    bool private s_revertOnDecimals;

    constructor(uint8 _decimals, int256 _answer) {
        s_decimals = _decimals;
        setAnswer(_answer);
    }

    /// @notice Sets a fresh answer at block.timestamp in a new, complete round.
    function setAnswer(int256 _answer) public {
        s_roundId++;
        s_answer = _answer;
        s_startedAt = block.timestamp;
        s_updatedAt = block.timestamp;
        s_answeredInRound = s_roundId;
    }

    /// @notice Sets every field returned by latestRoundData().
    function setRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external {
        s_roundId = _roundId;
        s_answer = _answer;
        s_startedAt = _updatedAt;
        s_updatedAt = _updatedAt;
        s_answeredInRound = _answeredInRound;
    }

    function setDecimals(uint8 _decimals) external {
        s_decimals = _decimals;
    }

    function setRevertOnLatestRoundData(bool _revert) external {
        s_revertOnLatestRoundData = _revert;
    }

    function setRevertOnDecimals(bool _revert) external {
        s_revertOnDecimals = _revert;
    }

    function decimals() external view returns (uint8) {
        if (s_revertOnDecimals) revert AggregatorConfigurableMock__Reverted();
        return s_decimals;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (s_revertOnLatestRoundData)
            revert AggregatorConfigurableMock__Reverted();
        return (s_roundId, s_answer, s_startedAt, s_updatedAt, s_answeredInRound);
    }
}
