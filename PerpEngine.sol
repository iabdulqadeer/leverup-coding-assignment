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
    uint256 public constant MAX_PRICE_AGE = 60 seconds;

    IERC20Minimal public immutable collateralToken;
    IOracle public immutable oracle;
    address public immutable owner;

    /// @notice Fees collected and not yet withdrawn.
    uint256 public accruedFees;

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
    error StalePrice();
    error NotLiquidatable();
    error TransferFailed();
    error InvalidAddress();
    error NotOwner();

    event PositionOpened(
        address indexed trader,
        uint256 margin,
        uint256 notional,
        uint256 entryPrice,
        bool isLong
    );

    event PositionClosed(address indexed trader, uint256 exitPrice, int256 pnl, uint256 returnedMargin);
    event PositionLiquidated(
        address indexed trader,
        address indexed liquidator,
        uint256 exitPrice,
        uint256 reward,
        uint256 returnedMargin
    );
    event FeesWithdrawn(address indexed to, uint256 amount);

    constructor(address collateralToken_, address oracle_) {
        if (collateralToken_ == address(0) || oracle_ == address(0)) revert InvalidAddress();

        collateralToken = IERC20Minimal(collateralToken_);
        oracle = IOracle(oracle_);
        owner = msg.sender;
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

        uint256 price = _getPrice();

        uint256 notional = margin * leverage;
        uint256 fee = _bpsRoundedUp(notional, FEE_BPS);
        uint256 netMargin = margin - fee;

        // Maintenance is charged on notional, so leverage above 181x is below maintenance
        // as soon as the fee is taken. Such a position could be liquidated immediately.
        if (netMargin < _bpsRoundedUp(notional, MAINTENANCE_BPS)) revert InvalidLeverage();

        current.margin = netMargin;
        current.notional = notional;
        current.entryPrice = price;
        current.isLong = isLong;
        accruedFees += fee;

        _callToken(abi.encodeCall(IERC20Minimal.transferFrom, (msg.sender, address(this), margin)));

        emit PositionOpened(msg.sender, netMargin, notional, price, isLong);
    }

    function closePosition() external {
        Position memory p = positions[msg.sender];
        if (p.notional == 0) revert NoPosition();

        uint256 price = _getPrice();

        int256 pnl = _calculatePnl(p, price);
        uint256 payout = _settlementAmount(p.margin, pnl);

        delete positions[msg.sender];

        if (payout > 0) _callToken(abi.encodeCall(IERC20Minimal.transfer, (msg.sender, payout)));

        emit PositionClosed(msg.sender, price, pnl, payout);
    }

    function liquidate(address trader) external {
        Position memory p = positions[trader];
        if (p.notional == 0) revert NoPosition();

        uint256 price = _getPrice();

        int256 pnl = _calculatePnl(p, price);
        uint256 equity = _equity(p.margin, pnl);

        if (equity >= _bpsRoundedUp(p.notional, MAINTENANCE_BPS)) revert NotLiquidatable();

        // The reward comes out of the trader's equity, so an underwater position pays none
        // and self-liquidating is never better than closing.
        uint256 reward = p.margin / 20;
        if (reward > equity) reward = equity;
        uint256 returnedMargin = equity - reward;

        delete positions[trader];

        if (reward > 0) _callToken(abi.encodeCall(IERC20Minimal.transfer, (msg.sender, reward)));
        if (returnedMargin > 0) _callToken(abi.encodeCall(IERC20Minimal.transfer, (trader, returnedMargin)));

        emit PositionLiquidated(trader, msg.sender, price, reward, returnedMargin);
    }

    function withdrawFees(address to) external {
        if (msg.sender != owner) revert NotOwner();
        if (to == address(0)) revert InvalidAddress();

        uint256 amount = accruedFees;
        accruedFees = 0;

        if (amount > 0) _callToken(abi.encodeCall(IERC20Minimal.transfer, (to, amount)));

        emit FeesWithdrawn(to, amount);
    }

    function _getPrice() internal view returns (uint256 price) {
        uint256 updatedAt;
        (price, updatedAt) = oracle.getPrice();

        if (price == 0) revert InvalidPrice();
        if (updatedAt > block.timestamp || block.timestamp - updatedAt > MAX_PRICE_AGE) revert StalePrice();
    }

    function _bpsRoundedUp(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps + BPS - 1) / BPS;
    }

    /// @dev Accepts tokens that return true or nothing. An empty return from an address
    /// with no code is a failure, because a low-level call to it always succeeds.
    function _callToken(bytes memory data) internal {
        (bool success, bytes memory result) = address(collateralToken).call(data);

        if (!success) revert TransferFailed();
        if (result.length == 0) {
            if (address(collateralToken).code.length == 0) revert TransferFailed();
        } else if (!abi.decode(result, (bool))) {
            revert TransferFailed();
        }
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
