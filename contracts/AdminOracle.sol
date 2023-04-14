// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title UniV2TwapOracle Contract
/// @dev Fixed window oracle that recomputes the average price for the entire period once every period
/// Note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract AdminOracle is Initializable, OwnableUpgradeable {
    using FixedPoint for *;

    /// @notice TWAP period
    uint256 public PERIOD;

    /// @notice Used for being able to consult past the period end
    uint256 public CONSULT_LENIENCY;

    /// @notice If false, consult() will fail if the TWAP is stale
    bool public ALLOW_STALE_CONSULTS;

    /// @notice token1 of the pair 
    address public token0;

    /// @notice token2 of the pair 
    address public token1;

    /// @notice last cumulative price of the first token of the pair
    uint256 public price0CumulativeLast;

    /// @notice last cumulative price of the second token of the pair
    uint256 public price1CumulativeLast;

    /// @notice Last updated timestamp
    uint32 public blockTimestampLast;

    /// @notice Average price of token0
    FixedPoint.uq112x112 public price0Average;

    /// @notice Average price of token1 
    FixedPoint.uq112x112 public price1Average;

    error NoReserves();
    error PeriodNotElapsed();
    error PriceIsStale();
    error InvalidToken();

    /**
     * @notice Initializer
     * @param _token0 first token.
     * @param _token1 second token.
     * @param _price0Cumulative Cumulative price for token1.
     * @param _price1Cumulative Cumulative price for token2.
     * @param _consultLeniency Used for being able to consult past the period end.
     * @param _allowStaleConsults Enable/Disable stale.
     */
    function initialize(
        address _token0,
        address _token1,
        uint256 _price0Cumulative,
        uint256 _price1Cumulative,
        uint256 _period,
        uint256 _consultLeniency,
        bool _allowStaleConsults
    ) external initializer {
        token0 = _token0;
        token1 = _token1;
        price0CumulativeLast = _price0Cumulative;
        price1CumulativeLast = _price1Cumulative;
        PERIOD = _period;
        CONSULT_LENIENCY = _consultLeniency;
        ALLOW_STALE_CONSULTS = _allowStaleConsults;
    }

    /**
     * @notice Sets new period.
     * @param _period TWAP period.
     */
    function setPeriod(uint256 _period) external onlyOwner {
        PERIOD = _period;
    }

    /**
     * @notice Sets new consult leniency.
     * @param _consultLeniency new value.
     */
    function setConsultLeniency(uint256 _consultLeniency) external onlyOwner {
        CONSULT_LENIENCY = _consultLeniency;
    }

    /**
     * @notice Sets stale consult option.
     * @param _allowStaleConsults new value.
     */
    function setAllowStaleConsults(bool _allowStaleConsults)
        external
        onlyOwner
    {
        ALLOW_STALE_CONSULTS = _allowStaleConsults;
    }

    /**
     * @dev Check if update() can be called instead of wasting gas calling it.
     */
    function canUpdate() public view returns (bool) {
        uint32 timeElapsed = block.timestamp - blockTimestampLast; // Overflow is desired
        return (timeElapsed >= PERIOD);
    }

    /**
     * @notice Updates price
     */
    function update(uint256 price0Cumulative, uint256 price1Cumulative) external onlyOwner {
        uint32 timeElapsed = block.timestamp - blockTimestampLast; // Overflow is desired

        // Ensure that at least one full period has passed since the last update
        if (timeElapsed < PERIOD) revert PeriodNotElapsed();

        // Overflow is desired, casting never truncates
        // Cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
        );
        price1Average = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
        );
        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = block.timestamp;
    }

    /**
     * @dev This will always return 0 before update has been called successfully for the first time.
     */
    function _consult(address _token, uint256 _amountIn)
        internal
        view
        returns (uint256 amountOut)
    {
        uint32 timeElapsed = block.timestamp - blockTimestampLast; // Overflow is desired

        // Ensure that the price is not stale
        if((timeElapsed >= (PERIOD + CONSULT_LENIENCY)) && !ALLOW_STALE_CONSULTS)
            revert PriceIsStale();
        if (_token == token0) {
            amountOut = price0Average.mul(_amountIn).decode144();
        } else {
            if(_token != token1) revert InvalidToken();
            amountOut = price1Average.mul(_amountIn).decode144();
        }
    }

    /**
     * @notice Returns current price.
     */
    function consult() public view returns (uint256 amountOut) {
        uint8 decimals = IERC20Metadata(token0).decimals();
        return _consult(token0, 10**decimals);
    }
}