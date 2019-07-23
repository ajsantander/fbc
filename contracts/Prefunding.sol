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

    // TODO: Add docs
    ERC20 purchasingToken;

    // TODO: Add docs
    TokenManager projectTokenManager;
    MiniMeToken projectToken;

    // TODO: Add docs
    uint64 startDate;

    // TODO: Add docs
    uint256 totalRaised;

    // Initial amount in DAI required to be raised in order to start the project.
    uint256 fundingGoal;

    // Duration in which funds will be accepted.
    uint64 fundingPeriod;

    // TODO: Add docs
    uint64 vestingCliffDate;
    uint64 vestingCompleteDate;

    /*
     * Initializer 
     */

    function initialize(
        ERC20 _purchasingToken,
        MiniMeToken _projectToken,
        TokenManager _projectTokenManager,
        uint64 _vestingCliffDate,
        uint64 _vestingCompleteDate
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
    }

    /*
     * Modifiers
     */

    // TODO: Add docs.
    modifier validateState {
        if(_elapsedTime() > fundingPeriod) {
            if(totalRaised < fundingGoal) _updateState(PrefundingState.Refunding);
            else _updateState(PrefundingState.Closed);
        }
        _;
    }

    /*
     * Public
     */

    function start() public auth(START_ROLE) {
        require(currentState == PrefundingState.Pending, ERROR_INVALID_STATE);
        startDate = getTimestamp64();
        _updateState(PrefundingState.Funding);
    }

    function buy(uint256 _purchasingTokenAmountToSpend) public validateState auth(BUY_ROLE) {
        require(currentState == PrefundingState.Funding, ERROR_INVALID_STATE);
        require(purchasingToken.balanceOf(msg.sender) >= _purchasingTokenAmountToSpend, ERROR_INSUFFICIENT_FUNDS);
        require(purchasingToken.allowance(msg.sender, address(this)) >= _purchasingTokenAmountToSpend, ERROR_INSUFFICIENT_ALLOWANCE);

        // Calculate the amount of project tokens that will be sold
        // for the provided purchasing token amount.
        uint256 projectTokenAmountToSell = 1;
        // TODO

        // Transfer purchasingTokens to this contract.
        purchasingToken.transferFrom(msg.sender, address(this), _purchasingTokenAmountToSpend);

        // Transger projectTokens to the sender (in vested form).
        projectTokenManager.assignVested(
            msg.sender,
            projectTokenAmountToSell,
            startDate,
            vestingCliffDate,
            vestingCompleteDate,
            true /* revokable */
        );
    }

    function refund() public validateState {
        require(currentState == PrefundingState.Refunding, ERROR_INVALID_STATE);

        // TODO
    }

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

    function _elapsedTime() internal returns (uint64) {
        if(startDate == 0) return 0;
        else return getTimestamp64().sub(startDate);
    }
}
