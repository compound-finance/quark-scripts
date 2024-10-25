// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {AggregatorV3Interface} from "src/vendor/chainlink/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    uint8 public override decimals = 8;
    string public override description = "Mock Price Feed";
    uint256 public override version = 1;

    int256 public latestAnswer;
    uint256 public latestTimestamp;

    function setLatestAnswer(int256 _answer, uint256 _updatedAt) external {
        latestAnswer = _answer;
        latestTimestamp = _updatedAt;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, latestAnswer, 0, latestTimestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, latestAnswer, 0, latestTimestamp, 0);
    }
}
