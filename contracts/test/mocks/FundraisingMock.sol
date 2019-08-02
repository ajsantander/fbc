pragma solidity ^0.4.24;

contract FundraisingMock {

    address public token;
    uint256 public virtualSupply;
    uint256 public virtualBalance;
    uint32 public reserveRatio;
    uint256 public tap;

    function addCollateralToken(
        address _token,
        uint256 _virtualSupply,
        uint256 _virtualBalance,
        uint32 _reserveRatio,
        uint256 _tap
    )
    	external
    {
        token = _token;
        virtualSupply = _virtualSupply;
        virtualBalance = _virtualBalance;
        reserveRatio = _reserveRatio;
        tap = _tap;
    }
}
