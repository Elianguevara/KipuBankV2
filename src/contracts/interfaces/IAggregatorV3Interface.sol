// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IAggregatorV3Interface
 * @notice Minimal Chainlink AggregatorV3 interface for price feeds.
 * @dev Provides latest price data and decimals used by the feed.
 */
interface IAggregatorV3Interface {
    /// @notice Returns the number of decimals the aggregator responses represent.
    function decimals() external view returns (uint8);

    /// @notice Returns the latest round data.
    /// @return roundId The round ID.
    /// @return answer The price.
    /// @return startedAt Timestamp when the round started.
    /// @return updatedAt Timestamp when the round was last updated.
    /// @return answeredInRound The round in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
