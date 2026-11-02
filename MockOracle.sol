// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal oracle used by the coding assignment.
contract MockOracle {
    address public immutable owner;

    uint256 private _price;
    uint256 private _updatedAt;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint256 initialPrice) {
        owner = msg.sender;
        _price = initialPrice;
        _updatedAt = block.timestamp;
    }

    function setPrice(uint256 newPrice) external onlyOwner {
        _price = newPrice;
        _updatedAt = block.timestamp;
    }

    function setPriceAndTimestamp(uint256 newPrice, uint256 timestamp_) external onlyOwner {
        _price = newPrice;
        _updatedAt = timestamp_;
    }

    function getPrice() external view returns (uint256 price, uint256 updatedAt) {
        return (_price, _updatedAt);
    }
}
