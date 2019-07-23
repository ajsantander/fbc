pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/IForwarder.sol";

import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/math/SafeMath64.sol";

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

    string internal constant ERROR_INVALID_STATE = "PREFUNDING_INVALID_STATE";
    string internal constant ERROR_CAN_NOT_FORWARD = "CAN_NOT_FORWARD";

    /*
     * Roles.
     */

    bytes32 public constant START_ROLE = keccak256("START_ROLE");
    bytes32 public constant BUY_ROLE = keccak256("BUY_ROLE");

    /*
     * Properties
     */

    enum PrefundingState {
        Pending, // Initial state. Prefunding is closed and waiting to be started.
        Funding, // Prefunding has started, and contributors can purchase tokens.
        Refunding, // Prefunding did not reach fundingGoal, and contributors may retrieve their funds.
        Closed // Prefunding reached fundingGoal, and the Fundraising app is ready to be initialized.
    }

    PrefundingState public currentState;

    // TODO: Add docs
    uint64 startDate;

    // TODO: Add docs
    uint256 totalRaised;

    // Initial amount in DAI required to be raised in order to start the project.
    uint256 fundingGoal;

    // Duration in which funds will be accepted.
    uint64 fundingPeriod;

    /*
     * Initializer 
     */

    function initialize() external onlyInit {
        initialized();

        currentState = PrefundingState.Pending;

        // ...
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

        // TODO
    }

    function buy() public validateState auth(BUY_ROLE) {
        require(currentState == PrefundingState.Funding, ERROR_INVALID_STATE);

        // TODO
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
        return getTimestamp64().sub(startDate);
    }
}
