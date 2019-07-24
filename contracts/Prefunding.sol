pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/IForwarder.sol";

import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/math/SafeMath64.sol";

import "@aragon/os/contracts/lib/token/ERC20.sol";
import "@aragon/apps-shared-minime/contracts/MiniMeToken.sol";
import "@aragon/apps-token-manager/contracts/TokenManager.sol";

contract Prefunding is IForwarder, AragonApp {
    using SafeMath for uint256;
    using SafeMath64 for uint64;

    event SaleStateChanged(SaleState newState);
    event ProjectTokensPurchased(address indexed owner, uint256 purchaseTokensSpent, uint256 projectTokensSold);

    string private constant ERROR_INVALID_STATE = "INVALID_STATE";
    string private constant ERROR_CAN_NOT_FORWARD = "CAN_NOT_FORWARD";
    string private constant ERROR_INSUFFICIENT_ALLOWANCE = "INSUFFICIENT_ALLOWANCE";
    string private constant ERROR_INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS";
    string private constant ERROR_INVALID_TOKEN_CONTROLLER = "INVALID_TOKEN_CONTROLLER";

    bytes32 public constant START_ROLE = keccak256("START_ROLE");
    bytes32 public constant BUY_ROLE = keccak256("BUY_ROLE");

    enum SaleState {
        Pending,   // Sale is closed and waiting to be started.
        Funding,   // Sale has started and contributors can purchase tokens.
        Refunding, // Sale did not reach fundingGoal and contributors may retrieve their funds.
        Closed     // Sale reached fundingGoal and the Fundraising app is ready to be initialized.
    }

    SaleState public _currentSaleState;

    ERC20 private _purchasingToken;
    MiniMeToken private _projectToken;
    TokenManager private _projectTokenManager;

    uint64 private _startDate;

    uint256 private _totalRaised;
    uint256 private _fundingGoal;
    uint64 private _fundingPeriod;

    uint64 private _vestingCliffDate;
    uint64 private _vestingCompleteDate;

    uint256 private _percentSupplyOffered;
    uint256 private _purchaseTokenExchangeRate;

    uint256 private constant PRECISION_MULTIPLIER = 10 ** 16;
    uint256 private constant CONNECTOR_WEIGHT = 10;

    modifier validateState {
        if(_timeSinceFundingStarted() > _fundingPeriod) {
            if(_totalRaised < _fundingGoal) _updateState(SaleState.Refunding);
            else _updateState(SaleState.Closed);
        }
        _;
    }

    function initialize(
        ERC20 purchasingToken,
        MiniMeToken projectToken,
        TokenManager projectTokenManager,
        uint64 vestingCliffDate,
        uint64 vestingCompleteDate,
        uint256 fundingGoal,
        uint256 percentSupplyOffered
    ) 
        external 
        onlyInit 
    {
        initialized();

        _purchasingToken = purchasingToken;
        _setProjectToken(projectToken, projectTokenManager);

        // TODO: Perform validations regarding vesting and prefunding dates.
        // EG: Verify that versting cliff > sale period, otherwise
        // contributors would be able to exchange tokens before the sale ends.
        // EG: Verify that vesting complete date < vesting cliff date.
        _vestingCliffDate = vestingCliffDate;
        _vestingCompleteDate = vestingCompleteDate;

        // TODO: Validate
        _fundingGoal = fundingGoal;
        _percentSupplyOffered = percentSupplyOffered;

        _calculateExchangeRate();
    }

    function start() public auth(START_ROLE) {
        require(_currentSaleState == SaleState.Pending, ERROR_INVALID_STATE);
        _startDate = getTimestamp64();
        _updateState(SaleState.Funding);
    }

    function buy(uint256 purchasingTokenAmountToSpend) public validateState auth(BUY_ROLE) {
        require(_currentSaleState == SaleState.Funding, ERROR_INVALID_STATE);
        require(_purchasingToken.balanceOf(msg.sender) >= purchasingTokenAmountToSpend, ERROR_INSUFFICIENT_FUNDS);
        require(_purchasingToken.allowance(msg.sender, address(this)) >= purchasingTokenAmountToSpend, ERROR_INSUFFICIENT_ALLOWANCE);

        // Calculate the amount of project tokens that will be sold
        // for the provided purchasing token amount.
        uint256 projectTokenAmountToSell = getProjectTokenAmount(purchasingTokenAmountToSpend);

        // Transfer purchasingTokens to this contract.
        _purchasingToken.transferFrom(msg.sender, address(this), purchasingTokenAmountToSpend);

        // Transfer projectTokens to the sender (in vested form).
        // TODO: This assumes that msg.sender will not actually
        // own the tokens before this sale ends. Make sure to validate that,
        // because it would represent a critical issue otherwise.
        _projectTokenManager.assignVested(
            msg.sender,
            projectTokenAmountToSell,
            _startDate,
            _vestingCliffDate,
            _vestingCompleteDate,
            true /* revokable */
        );

        emit ProjectTokensPurchased(msg.sender, purchasingTokenAmountToSpend, projectTokenAmountToSell);
    }

    function refund() public validateState {
        require(_currentSaleState == SaleState.Refunding, ERROR_INVALID_STATE);
        // TODO
    }

    function close() public validateState {
        require(_currentSaleState == SaleState.Closed, ERROR_INVALID_STATE);
        // TODO
    }

    // TODO: This could have a better name.
    function getProjectTokenAmount(uint256 purchasingTokenAmountToSpend) public view returns (uint256) {
        return purchasingTokenAmountToSpend.mul(_purchaseTokenExchangeRate);
    }

    function isForwarder() external pure returns (bool) {
        return true;
    }

    function forward(bytes evmScript) public {
        require(canForward(msg.sender, evmScript), ERROR_CAN_NOT_FORWARD);
        // TODO
    }

    function canForward(address sender, bytes) public view returns (bool) {
        // TODO
        return true;
    }

    function _updateState(SaleState newState) private {
        if(newState != _currentSaleState) {
            _currentSaleState = newState;
            emit SaleStateChanged(newState);
        }
    }

    function _timeSinceFundingStarted() private returns (uint64) {
        if(_startDate == 0) return 0;
        else return getTimestamp64().sub(_startDate);
    }

    function _calculateExchangeRate() private {
        uint256 exchangeRate = _fundingGoal.mul(PRECISION_MULTIPLIER).div(CONNECTOR_WEIGHT);
        exchangeRate = exchangeRate.mul(100).div(_percentSupplyOffered);
        exchangeRate = exchangeRate.div(PRECISION_MULTIPLIER);
        _purchaseTokenExchangeRate = exchangeRate;
    }

    function _setProjectToken(MiniMeToken projectToken, TokenManager projectTokenManager) private {
        require(isContract(projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        require(projectToken.controller() == address(projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        _projectToken = projectToken;
        _projectTokenManager = projectTokenManager;
    }

    function getProjectToken() public view returns (address) { return address(_projectToken); }
    function getProjectTokenManager() public view returns (address) { return address(_projectTokenManager); }
    function getPurchasingToken() public view returns (address) { return address(_purchasingToken); }
    function getCurrentSaleState() public view returns (SaleState) { return _currentSaleState; }
    function getFundingGoal() public view returns (uint256) { return _fundingGoal; }
    function getTotalRaised() public view returns (uint256) { return _totalRaised; }
    function getPercentSupplyOffered() public view returns (uint256) { return _percentSupplyOffered; }
    function getVestingCliffDate() public view returns (uint64) { return _vestingCliffDate; }
    function getVestingCompleteDate() public view returns (uint64) { return _vestingCompleteDate; }
}
