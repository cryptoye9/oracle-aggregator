// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract BaseOracle is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    address public ethChainlinkFeed;
    bool public FALLBACK_ENABLED;

    IBaseOracle public fallbackOracle;
    
    error ZeroAddress();
    error FallbackWasNotSet();

    function baseInitialize(
        address _ethChainlinkFeed
    ) internal onlyInitializing {
        ethChainlinkFeed = _ethChainlinkFeed;
    }

    function setFallback(address _fallback) public onlyOwner {
        if(_fallback == address(0)) revert ZeroAddress();
        fallbackOracle = IBaseOracle(_fallback);
    }

    function enableFallback(bool _enabled) public onlyOwner {
        if(address(fallbackOracle) == (address(0))) revert FallbackWasNotSet();
        FALLBACK_ENABLED = _enabled;
    }

    // implement in child contract
    function consult() public view virtual returns (uint amountOut) {}

    // supports 18 decimal token
    // returns USD price in decimal 8
    function latestAnswer() public view returns (uint256 price) {
        // returns decimals 18
        uint256 priceInEth = latestAnswerInEth();
        
        // returns decimals 8
        uint256 ethPrice = uint256(
            IChainlinkAggregator(ethChainlinkFeed).latestAnswer()
        );
        
        price = priceInEth.mul(ethPrice).div(10 ** 8);
    }

    // supports 18 decimal token
    // returns TOKEN price in ETH w/ decimal 8
    function latestAnswerInEth() public view returns (uint256 price) {
        if(!FALLBACK_ENABLED) {
            price = consult();
        } else {
            price = fallbackOracle.consult();
        }
        price = price.div(10 ** 10);
    }

    function canUpdate() public view virtual returns (bool) {
        return false;
    }
}