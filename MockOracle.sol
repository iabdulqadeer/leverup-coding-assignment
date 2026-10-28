// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal oracle used by the coding assignment.
contract MockOracle {
    uint256 private _price;
    uint256 private _updatedAt;

    constructor(uint256 initialPrice) {
        _price = initialPrice;
        _updatedAt = block.timestamp;
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
        _updatedAt = block.timestamp;
    }

    function setPriceAndTimestamp(uint256 newPrice, uint256 timestamp_) external {
        _price = newPrice;
        _updatedAt = timestamp_;
    }

    function getPrice() external view returns (uint256 price, uint256 updatedAt) {
        return (_price, _updatedAt);
    }
}
