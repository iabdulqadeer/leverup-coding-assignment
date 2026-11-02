// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPositions {
    function positions(address trader)
        external
        view
        returns (uint256 margin, uint256 notional, uint256 entryPrice, bool isLong);
}

/// @notice Token that returns no value (USDT-style) and records engine state during transferFrom.
contract TestToken {
    mapping(address => uint256) public balanceOf;
    IPositions public engine;
    uint256 public notionalSeenDuringTransfer;

    function setEngine(IPositions engine_) external {
        engine = engine_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        (, notionalSeenDuringTransfer, , ) = engine.positions(from);
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}
