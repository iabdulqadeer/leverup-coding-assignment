// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOracle {
    function getPrice() external view returns (uint256 price, uint256 updatedAt);
}

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Compact perpetual-position engine for the LeverUp coding assignment.
///
/// The contract is intentionally small. Several bugs are present and are expected
/// to be found and fixed by the candidate.
contract LeverUpPerpEngine {
    uint256 public constant MAX_LEVERAGE = 1001;
    uint256 public constant MAINTENANCE_BPS = 50; // 0.50%
    uint256 public constant FEE_BPS = 5; // 0.05%
    uint256 public constant BPS = 10_000;

    uint256 public constant PRICE_DECIMALS = 1e8;
    uint256 public constant TOKEN_DECIMALS = 1e6;

    IERC20Minimal public immutable collateralToken;
    IOracle public immutable oracle;

    struct Position {
        uint256 margin;
        uint256 notional;
        uint256 entryPrice;
        bool isLong;
    }

    mapping(address => Position) public positions;

    error PositionAlreadyOpen();
    error NoPosition();
    error InvalidMargin();
    error InvalidLeverage();
    error InvalidPrice();
    error NotLiquidatable();
    error TransferFailed();

    event PositionOpened(
        address indexed trader,
        uint256 margin,
        uint256 notional,
        uint256 entryPrice,
        bool isLong
    );

    event PositionClosed(address indexed trader, uint256 exitPrice, int256 pnl, uint256 returnedMargin);
    event PositionLiquidated(address indexed trader, address indexed liquidator, uint256 exitPrice, uint256 reward);

    constructor(address collateralToken_, address oracle_) {
        collateralToken = IERC20Minimal(collateralToken_);
        oracle = IOracle(oracle_);
    }

    function openPosition(
        uint256 margin,
        uint256 leverage,
        bool isLong
    ) external {
        Position storage current = positions[msg.sender];
        if (current.notional != 0) revert PositionAlreadyOpen();
        if (margin == 0) revert InvalidMargin();
        if (leverage == 0 || leverage > MAX_LEVERAGE) revert InvalidLeverage();

        (uint256 price, ) = oracle.getPrice();
        if (price == 0) revert InvalidPrice();

        uint256 notional = margin * leverage;
        uint256 fee = (notional * FEE_BPS) / BPS;

        if (!collateralToken.transferFrom(msg.sender, address(this), margin)) {
            revert TransferFailed();
        }

        current.margin = margin - fee;
        current.notional = notional;
        current.entryPrice = price;
        current.isLong = isLong;

        emit PositionOpened(msg.sender, margin, notional, price, isLong);
    }

    function closePosition() external {
        Position memory p = positions[msg.sender];
        if (p.notional == 0) revert NoPosition();

        (uint256 price, ) = oracle.getPrice();
        if (price == 0) revert InvalidPrice();

        int256 pnl = _calculatePnl(p, price);
        uint256 payout = _settlementAmount(p.margin, pnl);

        delete positions[msg.sender];

        if (payout > 0 && !collateralToken.transfer(msg.sender, payout)) {
            revert TransferFailed();
        }

        emit PositionClosed(msg.sender, price, pnl, payout);
    }

    function liquidate(address trader) external {
        Position memory p = positions[trader];
        if (p.notional == 0) revert NoPosition();

        (uint256 price, ) = oracle.getPrice();
        if (price == 0) revert InvalidPrice();

        int256 pnl = _calculatePnl(p, price);
        uint256 equity = _equity(p.margin, pnl);
        uint256 maintenance = (p.notional * MAINTENANCE_BPS) / BPS;

        if (equity > maintenance) revert NotLiquidatable();

        uint256 reward = p.margin / 20;

        delete positions[trader];

        if (reward > 0 && !collateralToken.transfer(msg.sender, reward)) {
            revert TransferFailed();
        }

        emit PositionLiquidated(trader, msg.sender, price, reward);
    }

    function _calculatePnl(Position memory p, uint256 exitPrice) internal pure returns (int256) {
        if (p.isLong) {
            return int256((p.notional * exitPrice) / p.entryPrice) - int256(p.notional);
        }

        return int256(p.notional) - int256((p.notional * exitPrice) / p.entryPrice);
    }

    function _equity(uint256 margin, int256 pnl) internal pure returns (uint256) {
        if (pnl >= 0) {
            return margin + uint256(pnl);
        }

        uint256 loss = uint256(-pnl);
        return loss >= margin ? 0 : margin - loss;
    }

    function _settlementAmount(uint256 margin, int256 pnl) internal pure returns (uint256) {
        if (pnl >= 0) {
            return margin + uint256(pnl);
        }

        uint256 loss = uint256(-pnl);
        return loss >= margin ? 0 : margin - loss;
    }
}
