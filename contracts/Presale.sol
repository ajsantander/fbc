pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";

import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/math/SafeMath64.sol";

import "@aragon/os/contracts/lib/token/ERC20.sol";
import "@aragon/apps-shared-minime/contracts/MiniMeToken.sol";
import "@aragon/apps-token-manager/contracts/TokenManager.sol";

import "@ablack/controller-aragon-fundraising/contracts/AragonFundraisingController.sol";


contract Presale is AragonApp {
    using SafeMath for uint256;
    using SafeMath64 for uint64;

    event SaleStateChanged(SaleState newState);
    event TokensPurchased(address indexed buyer, uint256 daiSpent, uint256 tokensPurchased);

    string private constant ERROR_INVALID_STATE = "PRESALE_INVALID_STATE";
    string private constant ERROR_CAN_NOT_FORWARD = "PRESALE_CAN_NOT_FORWARD";
    string private constant ERROR_INSUFFICIENT_DAI_ALLOWANCE = "PRESALE_INSUFFICIENT_DAI_ALLOWANCE";
    string private constant ERROR_INSUFFICIENT_DAI = "PRESALE_INSUFFICIENT_DAI";
    string private constant ERROR_INVALID_TOKEN_CONTROLLER = "PRESALE_INVALID_TOKEN_CONTROLLER";
    string private constant ERROR_NOTHING_TO_REFUND = "PRESALE_NOTHING_TO_REFUND";
    string private constant ERROR_DAI_TRANSFER_REVERTED = "PRESALE_DAI_TRANSFER_REVERTED";

    bytes32 public constant START_ROLE = keccak256("START_ROLE");
    bytes32 public constant BUY_ROLE = keccak256("BUY_ROLE");

    ERC20 public daiToken;
    MiniMeToken public projectToken;
    TokenManager public projectTokenManager;

    uint64 public startDate;

    uint256 public totalDaiRaised;
    uint256 public daiFundingGoal;
    uint64 public fundingPeriod;

    AragonFundraisingController fundraisingController;
    address public fundraisingPool;
    uint256 tapRate;

    uint64 public vestingCliffDate;
    uint64 public vestingCompleteDate;

    uint256 public percentSupplyOffered;
    uint256 public daiToProjectTokenMultiplier;

    uint256 public constant PRECISION_MULTIPLIER = 10 ** 16;
    uint32 public constant CONNECTOR_WEIGHT_INV = 10;

    // Keeps track of how much dai is spent, per purchase, per buyer.
    mapping(address => mapping(uint256 => uint256)) purchases;
    /*      |                  |          |
     *      |                  |          daiSpent
     *      |                  purchaseId
     *      buyer
     */

    enum SaleState {
        Pending,   // Sale is closed and waiting to be started.
        Funding,   // Sale has started and contributors can purchase tokens.
        Refunding, // Sale did not reach daiFundingGoal and contributors may retrieve their funds.
        Closed     // Sale reached daiFundingGoal and the Fundraising app is ready to be initialized.
    }

    /*
     * Initialization
     */

    function initialize(
        ERC20 _daiToken,
        MiniMeToken _projectToken,
        TokenManager _projectTokenManager,
        uint64 _vestingCliffDate,
        uint64 _vestingCompleteDate,
        uint256 _daiFundingGoal,
        uint256 _percentSupplyOffered,
        uint64 _fundingPeriod,
        address _fundraisingPool,
        AragonFundraisingController _fundraisingController,
        uint256 _tapRate
    )
        external
        onlyInit
    {
        initialized();

        daiToken = _daiToken;
        _setProjectToken(_projectToken, _projectTokenManager);

        // TODO: Verify
        fundraisingController = _fundraisingController;
        fundraisingPool = _fundraisingPool;
        tapRate = _tapRate;

        // TODO: Perform validations regarding vesting and prefunding dates.
        // EG: Verify that versting cliff > sale period, otherwise
        // contributors would be able to exchange tokens before the sale ends.
        // EG: Verify that vesting complete date < vesting cliff date.
        vestingCliffDate = _vestingCliffDate;
        vestingCompleteDate = _vestingCompleteDate;

        // TODO: Validate
        fundingPeriod = _fundingPeriod;
        daiFundingGoal = _daiFundingGoal;
        percentSupplyOffered = _percentSupplyOffered;

        _calculateExchangeRate();
    }

    /*
     * Public interface
     */

    function start() public auth(START_ROLE) {
        require(currentSaleState() == SaleState.Pending, ERROR_INVALID_STATE);
        startDate = getTimestamp64();
    }

    function buy(uint256 _daiToSpend) public auth(BUY_ROLE) returns (uint256) {
        require(currentSaleState() == SaleState.Funding, ERROR_INVALID_STATE);
        require(daiToken.balanceOf(msg.sender) >= _daiToSpend, ERROR_INSUFFICIENT_DAI);
        require(daiToken.allowance(msg.sender, address(this)) >= _daiToSpend, ERROR_INSUFFICIENT_DAI_ALLOWANCE);

        require(daiToken.transferFrom(msg.sender, address(this), _daiToSpend), ERROR_DAI_TRANSFER_REVERTED);

        uint256 tokensToSell = daiToProjectTokens(_daiToSpend);
        // TODO: This assumes that msg.sender will not actually
        // own the tokens before this sale ends. Make sure to validate that,
        // because it would represent a critical issue otherwise.
        projectTokenManager.issue(tokensToSell);
        uint256 purchaseId = projectTokenManager.assignVested(
            msg.sender,
            tokensToSell,
            startDate,
            vestingCliffDate,
            vestingCompleteDate,
            true /* revokable */
        );

        totalDaiRaised = totalDaiRaised.add(_daiToSpend);
        purchases[msg.sender][purchaseId] = _daiToSpend;

        emit TokensPurchased(msg.sender, _daiToSpend, tokensToSell);

        return purchaseId;
    }

    function refund(address _buyer, uint256 _purchaseId) public {
        require(currentSaleState() == SaleState.Refunding, ERROR_INVALID_STATE);

        uint256 daiToRefund = purchases[_buyer][_purchaseId];
        require(daiToRefund > 0, ERROR_NOTHING_TO_REFUND);

        purchases[_buyer][_purchaseId] = 0;
        require(daiToken.transfer(_buyer, daiToRefund), ERROR_DAI_TRANSFER_REVERTED);

        (uint256 tokensSold,,,,,) = projectTokenManager.getVesting(_buyer, _purchaseId);
        // TODO: This assumes that the buyer did not transfer any of the vested tokens,
        // because the sale doesn't allow any transfers before its end date
        projectTokenManager.revokeVesting(_buyer, _purchaseId);
        projectTokenManager.burn(address(projectTokenManager), tokensSold);
    }

    function close() public {
        require(currentSaleState() == SaleState.Closed, ERROR_INVALID_STATE);

        require(daiToken.transfer(fundraisingPool, totalDaiRaised), ERROR_DAI_TRANSFER_REVERTED);

        fundraisingController.addCollateralToken(
            daiToken,
            0,
            0,
            CONNECTOR_WEIGHT_INV,
            tapRate
        );
    }

    /*
     * Getters
     */

    function daiToProjectTokens(uint256 _daiAmount) public view returns (uint256) {
        return _daiAmount.mul(daiToProjectTokenMultiplier);
    }

    function currentSaleState() public view returns (SaleState) {
        if (startDate == 0) {
            return SaleState.Pending;
        } else if (_timeSinceFundingStarted() < fundingPeriod) {
            return SaleState.Funding;
        } else {
            if (totalDaiRaised < daiFundingGoal) {
                return SaleState.Refunding;
            } else {
                return SaleState.Closed;
            }
        }
    }

    /*
     * Internal
     */

    function _timeSinceFundingStarted() private returns (uint64) {
        if (startDate == 0) {
            return 0;
        } else {
            return getTimestamp64().sub(startDate);
        }
    }

    function _calculateExchangeRate() private {
        uint256 connectorWeightInv = uint256(CONNECTOR_WEIGHT_INV);
        uint256 exchangeRate = daiFundingGoal.mul(PRECISION_MULTIPLIER).div(connectorWeightInv);
        exchangeRate = exchangeRate.mul(100).div(percentSupplyOffered);
        exchangeRate = exchangeRate.div(PRECISION_MULTIPLIER);
        daiToProjectTokenMultiplier = exchangeRate;
    }

    function _setProjectToken(MiniMeToken _projectToken, TokenManager _projectTokenManager) private {
        require(isContract(_projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        require(_projectToken.controller() != address(projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        projectToken = _projectToken;
        projectTokenManager = _projectTokenManager;
    }
}
