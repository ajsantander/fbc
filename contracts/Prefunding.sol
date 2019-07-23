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

    /*
     * Events
     */

    event PrefundingStateChanged(PrefundingState _newState);
    event ProjectTokensPurchased(address indexed owner, uint256 _purchaseTokensSpent, uint256 _projectTokensSold);

    /*
     * Errors
     */

    string internal constant ERROR_INVALID_STATE = "INVALID_STATE";
    string internal constant ERROR_CAN_NOT_FORWARD = "CAN_NOT_FORWARD";
    string internal constant ERROR_INSUFFICIENT_ALLOWANCE = "INSUFFICIENT_ALLOWANCE";
    string internal constant ERROR_INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS";
    string internal constant ERROR_INVALID_TOKEN_CONTROLLER = "INVALID_TOKEN_CONTROLLER";

    /*
     * Roles.
     */

    bytes32 public constant START_ROLE = keccak256("START_ROLE");
    bytes32 public constant BUY_ROLE = keccak256("BUY_ROLE");

    /*
     * Properties
     */

    enum PrefundingState {
        Pending,   // Initial state. Prefunding is closed and waiting to be started.
        Funding,   // Prefunding has started, and contributors can purchase tokens.
        Refunding, // Prefunding did not reach fundingGoal, and contributors may retrieve their funds.
        Closed     // Prefunding reached fundingGoal, and the Fundraising app is ready to be initialized.
    }

    PrefundingState public currentState;

    // Multiplier used to avoid losing precision when using division or calculating percentages.
    uint256 internal constant PRECISION_MULTIPLIER = 10 ** 16;

    // TODO: Add docs
    ERC20 purchasingToken;

    // TODO: Add docs
    TokenManager projectTokenManager;
    MiniMeToken projectToken;

    // TODO: Add docs
    uint64 public startDate;

    // TODO: Add docs
    uint256 public totalRaised;

    // Initial amount in DAI required to be raised in order to start the project.
    uint256 public fundingGoal;

    // Duration in which funds will be accepted.
    uint64 public fundingPeriod;

    // TODO: Add docs
    uint64 public vestingCliffDate;
    uint64 public vestingCompleteDate;

    // TODO: Add docs
    uint256 public constant purchaseTokenConnectorWeight = 10;

    // TODO: Add docs
    uint256 public purchaseTokenExchangeRate;

    // TODO: Add docs
    uint256 public percentSupplyOffered;

    /*
     * Initializer 
     */

    function initialize(
        ERC20 _purchasingToken,
        MiniMeToken _projectToken,
        TokenManager _projectTokenManager,
        uint64 _vestingCliffDate,
        uint64 _vestingCompleteDate,
        uint256 _fundingGoal,
        uint256 _percentSupplyOffered
    ) 
        external 
        onlyInit 
    {
        initialized();

        currentState = PrefundingState.Pending;

        purchasingToken = _purchasingToken;
        projectToken = _projectToken;

        // Verify the that the token manager is valid
        // and the current controller of the projectToken.
        require(isContract(_projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        require(_projectToken.controller() == address(_projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        projectTokenManager = _projectTokenManager;

        // TODO: Perform validations regarding vesting and prefunding dates.
        // EG: Verify that versting cliff > sale period, otherwise
        // contributors would be able to exchange tokens before the sale ends.
        // EG: Verify that vesting complete date < vesting cliff date.
        vestingCliffDate = _vestingCliffDate;
        vestingCompleteDate = _vestingCompleteDate;

        // TODO: Validate
        fundingGoal = _fundingGoal;

        // TODO: Validate
        percentSupplyOffered = _percentSupplyOffered;

        // Calculate purchaseTokenExchangeRate.
        uint256 exchangeRate = fundingGoal.mul(PRECISION_MULTIPLIER).div(purchaseTokenConnectorWeight);
        exchangeRate = exchangeRate.mul(100).div(percentSupplyOffered);
        exchangeRate = exchangeRate.div(PRECISION_MULTIPLIER);
        purchaseTokenExchangeRate = exchangeRate;
    }

    /*
     * Modifiers
     */

    // TODO: Add docs.
    modifier validateState {
        if(_timeSinceFundingStarted() > fundingPeriod) {
            if(totalRaised < fundingGoal) _updateState(PrefundingState.Refunding);
            else _updateState(PrefundingState.Closed);
        }
        _;
    }

    /*
     * Getters
     */

    // TODO: This could have a better name.
    function getProjectTokenAmount(uint256 _purchasingTokenAmountToSpend) public view returns (uint256) {
        return _purchasingTokenAmountToSpend * purchaseTokenExchangeRate;
    }

    /*
     * Public
     */

    // TODO: Add docs.
    function start() public auth(START_ROLE) {
        require(currentState == PrefundingState.Pending, ERROR_INVALID_STATE);
        startDate = getTimestamp64();
        _updateState(PrefundingState.Funding);
    }

    // TODO: Add docs.
    function buy(uint256 _purchasingTokenAmountToSpend) public validateState auth(BUY_ROLE) {
        require(currentState == PrefundingState.Funding, ERROR_INVALID_STATE);
        require(purchasingToken.balanceOf(msg.sender) >= _purchasingTokenAmountToSpend, ERROR_INSUFFICIENT_FUNDS);
        require(purchasingToken.allowance(msg.sender, address(this)) >= _purchasingTokenAmountToSpend, ERROR_INSUFFICIENT_ALLOWANCE);

        // Calculate the amount of project tokens that will be sold
        // for the provided purchasing token amount.
        uint256 projectTokenAmountToSell = getProjectTokenAmount(_purchasingTokenAmountToSpend);

        // Transfer purchasingTokens to this contract.
        purchasingToken.transferFrom(msg.sender, address(this), _purchasingTokenAmountToSpend);

        // Transfer projectTokens to the sender (in vested form).
        // TODO: This assumes that msg.sender will not actually
        // own the tokens before this sale ends. Make sure to validate that,
        // because it would represent a critical issue otherwise.
        projectTokenManager.assignVested(
            msg.sender,
            projectTokenAmountToSell,
            startDate,
            vestingCliffDate,
            vestingCompleteDate,
            true /* revokable */
        );

        emit ProjectTokensPurchased(msg.sender, _purchasingTokenAmountToSpend, projectTokenAmountToSell);
    }

    // TODO: Add docs.
    function refund() public validateState {
        require(currentState == PrefundingState.Refunding, ERROR_INVALID_STATE);

        // TODO
    }

    // TODO: Add docs.
    function close() public validateState {
        require(currentState == PrefundingState.Closed, ERROR_INVALID_STATE);

        // TODO
    }

    // This contract is explicitely not payable.
    function () external {}

    /*
     * IForwarder interface implementation.
     */

    function isForwarder() external pure returns (bool) {
        return true;
    }

    // TODO: Define
    function forward(bytes _evmScript) public {
        require(canForward(msg.sender, _evmScript), ERROR_CAN_NOT_FORWARD);
        // ...
    }

    // TODO: Define
    function canForward(address _sender, bytes) public view returns (bool) {
        // ...
        return true;
    }

    /*
     * Internal
     */

    function _updateState(PrefundingState _newState) internal {
        if(_newState != currentState) {
            currentState = _newState;
            emit PrefundingStateChanged(currentState);
        }
    }

    function _timeSinceFundingStarted() internal returns (uint64) {
        if(startDate == 0) return 0;
        else return getTimestamp64().sub(startDate);
    }
}
