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

    string private constant ERROR_INVALID_STATE = "PREFUND_INVALID_STATE";
    string private constant ERROR_CAN_NOT_FORWARD = "PREFUND_CAN_NOT_FORWARD";
    string private constant ERROR_INSUFFICIENT_ALLOWANCE = "PREFUND_INSUFFICIENT_ALLOWANCE";
    string private constant ERROR_INSUFFICIENT_FUNDS = "PREFUND_INSUFFICIENT_FUNDS";
    string private constant ERROR_INVALID_TOKEN_CONTROLLER = "PREFUND_INVALID_TOKEN_CONTROLLER";

    bytes32 public constant START_ROLE = keccak256("START_ROLE");
    bytes32 public constant BUY_ROLE = keccak256("BUY_ROLE");

    enum SaleState {
        Pending,   // Sale is closed and waiting to be started.
        Funding,   // Sale has started and contributors can purchase tokens.
        Refunding, // Sale did not reach fundingGoal and contributors may retrieve their funds.
        Closed     // Sale reached fundingGoal and the Fundraising app is ready to be initialized.
    }

    SaleState public currentSaleState;

    ERC20 public purchasingToken;
    MiniMeToken public projectToken;
    TokenManager public projectTokenManager;

    uint64 public startDate;

    uint256 public totalRaised;
    uint256 public fundingGoal;
    uint64 public fundingPeriod;

    uint64 public vestingCliffDate;
    uint64 public vestingCompleteDate;

    uint256 public percentSupplyOffered;
    uint256 public purchaseTokenExchangeRate;

    uint256 public constant PRECISION_MULTIPLIER = 10 ** 16;
    uint256 public constant CONNECTOR_WEIGHT_INV = 10;

    struct Purchase {
        uint256 purchaseTokensSpent;
        uint256 projectTokensGiven;
    }

    // Tracks how many purchase tokens were spent per purchase.
    mapping(address => mapping(uint256 => uint256)) spends;

    // TODO: Rename to refreshState
    modifier validateState {
        if (_timeSinceFundingStarted() > fundingPeriod) {
            if (totalRaised < fundingGoal) {
                _updateState(SaleState.Refunding);
            } else {
                _updateState(SaleState.Closed);
            }
        }
        _;
    }

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

        purchasingToken = _purchasingToken;
        _setProjectToken(_projectToken, _projectTokenManager);

        // TODO: Perform validations regarding vesting and prefunding dates.
        // EG: Verify that versting cliff > sale period, otherwise
        // contributors would be able to exchange tokens before the sale ends.
        // EG: Verify that vesting complete date < vesting cliff date.
        vestingCliffDate = _vestingCliffDate;
        vestingCompleteDate = _vestingCompleteDate;

        // TODO: Validate
        fundingGoal = _fundingGoal;
        percentSupplyOffered = _percentSupplyOffered;

        _calculateExchangeRate();
    }

    function start() public auth(START_ROLE) {
        require(currentSaleState == SaleState.Pending, ERROR_INVALID_STATE);
        startDate = getTimestamp64();
        _updateState(SaleState.Funding);
    }

    function buy(uint256 _purchasingTokenAmountToSpend) public validateState auth(BUY_ROLE) returns (uint256) {
        require(currentSaleState == SaleState.Funding, ERROR_INVALID_STATE);
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
        projectTokenManager.issue(projectTokenAmountToSell);
        uint256 vestingId = projectTokenManager.assignVested(
            msg.sender,
            projectTokenAmountToSell,
            startDate,
            vestingCliffDate,
            vestingCompleteDate,
            true /* revokable */
        );

        // Remember how many purchase tokens were spent by the buyer in this purchase.
        spends[msg.sender][vestingId] = _purchasingTokenAmountToSpend;

        emit ProjectTokensPurchased(msg.sender, _purchasingTokenAmountToSpend, projectTokenAmountToSell);

        return vestingId;
    }

    function refund(address _buyer, uint256 _vestingId) public validateState {
        require(currentSaleState == SaleState.Refunding, ERROR_INVALID_STATE);

        // Calculate how many purchase tokens to refund and project tokens to burn for the purchase being refunded.
        uint256 amountToRefund = spends[_buyer][_vestingId];
        (uint256 vestedAmount,,,,,) = projectTokenManager.getVesting(_buyer, _vestingId);

        // Return the purchase tokens to the buyer.
        purchasingToken.transferFrom(address(this), _buyer, amountToRefund);

        // Revoke the vested project tokens.
        // TODO: This assumes that the buyer did not transfer any of the vested tokens,
        // because the sale doesn't allow any transfers before its end date
        projectTokenManager.revokeVesting(_buyer, _vestingId);

        // Burn the project tokens.
        projectTokenManager.burn(address(this), vestedAmount);
    }

    function close() public validateState {
        require(currentSaleState == SaleState.Closed, ERROR_INVALID_STATE);
        // TODO
    }

    // TODO: This could have a better name.
    function getProjectTokenAmount(uint256 _purchasingTokenAmountToSpend) public view returns (uint256) {
        return _purchasingTokenAmountToSpend.mul(purchaseTokenExchangeRate);
    }

    function isForwarder() external pure returns (bool) {
        return true;
    }

    function forward(bytes _evmScript) public {
        require(canForward(msg.sender, _evmScript), ERROR_CAN_NOT_FORWARD);
        // TODO
    }

    function canForward(address _sender, bytes) public view returns (bool) {
        // TODO
        return true;
    }

    function _updateState(SaleState _newState) private {
        if (_newState != currentSaleState) {
            currentSaleState = _newState;
            emit SaleStateChanged(_newState);
        }
    }

    function _timeSinceFundingStarted() private returns (uint64) {
        if (startDate == 0) {
            return 0;
        } else {
            return getTimestamp64().sub(startDate);
        }
    }

    function _calculateExchangeRate() private {
        uint256 exchangeRate = fundingGoal.mul(PRECISION_MULTIPLIER).div(CONNECTOR_WEIGHT_INV);
        exchangeRate = exchangeRate.mul(100).div(percentSupplyOffered);
        exchangeRate = exchangeRate.div(PRECISION_MULTIPLIER);
        purchaseTokenExchangeRate = exchangeRate;
    }

    function _setProjectToken(MiniMeToken _projectToken, TokenManager _projectTokenManager) private {
        require(isContract(_projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        require(_projectToken.controller() != address(projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        projectToken = _projectToken;
        projectTokenManager = _projectTokenManager;
    }
}
