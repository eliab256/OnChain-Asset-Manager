// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Index is ERC20 {
    IERC20 public immutable i_asset0;
    IERC20 public immutable i_asset1;

    AggregatorV3Interface public immutable i_asset0PriceFeed;
    AggregatorV3Interface public immutable i_asset1PriceFeed;

    uint256 public s_weight0;
    uint256 public s_weight1;
    uint256 public s_feePercentage;

    constructor(
        string memory _name,
        string memory _symbol,
        address _asset0,
        address _asset1,
        uint256 _weight0,
        uint256 _weight1,
        address _asset0PriceFeed,
        address _asset1PriceFeed,
        uint256 _feePercentage
    ) ERC20(_name, _symbol) {
        i_asset0 = IERC20(_asset0);
        i_asset1 = IERC20(_asset1);

        s_weight0 = _weight0;
        s_weight1 = _weight1;
        s_feePercentage = _feePercentage;

        i_asset0PriceFeed = AggregatorV3Interface(_asset0PriceFeed);
        i_asset1PriceFeed = AggregatorV3Interface(_asset1PriceFeed);

        //i_asset0.transferFrom(msg.sender, address(this), _underlyingAmount0); //msg.sender è da sostituire
       // i_asset1.transferFrom(msg.sender, address(this), _underlyingAmount1); //msg.sender è da sostituire

        //mint shares a owner
    }

    function initialize(uint256 _underlyingAmount0) external /*onlyOwner*/ {
        i_asset0.transferFrom(msg.sender, address(this), _underlyingAmount0);
        
    }


    function getToken0Amount() view public returns (uint256){
        return i_asset0.balanceOf(address(this));
    }

    function getToken1Amount() view public returns (uint256){
        return i_asset1.balanceOf(address(this));
    }
}
