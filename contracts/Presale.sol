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

    event SaleStarted();
    event SaleClosed();
    event TokensPurchased(address indexed buyer, uint256 daiSpent, uint256 tokensPurchased, uint256 purchaseId);
    event TokensRefunded(address indexed buyer, uint256 daiRefunded, uint256 tokensBurned, uint256 purchaseId);

    string private constant ERROR_INVALID_STATE                  = "PRESALE_INVALID_STATE";
    string private constant ERROR_CAN_NOT_FORWARD                = "PRESALE_CAN_NOT_FORWARD";
    string private constant ERROR_INSUFFICIENT_DAI_ALLOWANCE     = "PRESALE_INSUFFICIENT_DAI_ALLOWANCE";
    string private constant ERROR_INSUFFICIENT_DAI               = "PRESALE_INSUFFICIENT_DAI";
    string private constant ERROR_INVALID_TOKEN_CONTROLLER       = "PRESALE_INVALID_TOKEN_CONTROLLER";
    string private constant ERROR_NOTHING_TO_REFUND              = "PRESALE_NOTHING_TO_REFUND";
    string private constant ERROR_DAI_TRANSFER_REVERTED          = "PRESALE_DAI_TRANSFER_REVERTED";
    string private constant ERROR_INVALID_DAI_TOKEN              = "PRESALE_INVALID_DAI_TOKEN";
    string private constant ERROR_INVALID_FUNDRAISING_CONTROLLER = "PRESALE_INVALID_FUNDRAISING_CONTROLLER";
    string private constant ERROR_INVALID_TIME_PERIOD            = "PRESALE_INVALID_TIME_PERIOD";
    string private constant ERROR_INVALID_DAI_FUNDING_GOAL       = "PRESALE_INVALID_DAI_FUNDING_GOAL";
    string private constant ERROR_INVALID_PERCENT_VALUE          = "PRESALE_INVALID_PERCENT_VALUE";
    string private constant ERROR_INVALID_TAP_RATE               = "PRESALE_INVALID_TAP_RATE";
    string private constant ERROR_INVALID_POOL                   = "PRESALE_INVALID_POOL";
    string private constant ERROR_INVALID_BENEFICIARY_ADDRESS    = "PRESALE_INVALID_BENEFICIARY_ADDRESS";

    bytes32 public constant START_ROLE = keccak256("START_ROLE");
    bytes32 public constant BUY_ROLE   = keccak256("BUY_ROLE");

    ERC20 public daiToken;
    MiniMeToken public projectToken;
    TokenManager public projectTokenManager;

    uint64 public startDate;

    uint256 public totalDaiRaised;
    uint64 public fundingPeriod;

    uint256 public daiFundingGoal;
    uint256 public percentFundingForBeneficiary; // Represented in PPM, see below
    address public beneficiaryAddress;

    AragonFundraisingController fundraisingController;
    address public fundraisingPool;
    uint256 public tapRate;

    uint64 public vestingCliffPeriod;
    uint64 public vestingCompletePeriod;

    uint256 public percentSupplyOffered; // Represented in PPM, see below
    uint256 public daiToProjectTokenMultiplier;

    uint256 public constant PPM = 1000000; // Percentages are represented in the PPM range (Parts per Million): 0 => 0%, 1000000 => 100%
    uint32 public constant CONNECTOR_WEIGHT_PPM = 100000; // 10%

    bool private fundraisingInitialized;

    // Keeps track of how much dai is spent, per purchase, per buyer.
    mapping(address => mapping(uint256 => uint256)) public purchases;
    /*      |                  |          |
     *      |                  |          daiSpent
     *      |                  purchaseId
     *      buyer
     */

    enum SaleState {
        Pending,     // Sale is idle and pending to be started.
        Funding,     // Sale has started and contributors can purchase tokens.
        Refunding,   // Sale did not reach daiFundingGoal within fundingPeriod and contributors may claim refunds.
        GoalReached, // Sale reached daiFundingGoal and the Fundraising app is ready to be initialized.
        Closed       // After GoalReached, sale was closed and the Fundraising app was initialized.
    }

    /*
     * Initialization
     */

    function initialize(
        ERC20 _daiToken,
        MiniMeToken _projectToken,
        TokenManager _projectTokenManager,
        uint64 _vestingCliffPeriod,
        uint64 _vestingCompletePeriod,
        uint256 _daiFundingGoal,
        uint256 _percentSupplyOffered,
        uint64 _fundingPeriod,
        address _fundraisingPool,
        AragonFundraisingController _fundraisingController,
        uint256 _tapRate,
        address _beneficiaryAddress,
        uint256 _percentFundingForBenefiriary
    )
        external
        onlyInit
    {
        require(isContract(_daiToken), ERROR_INVALID_DAI_TOKEN);
        require(isContract(_fundraisingController), ERROR_INVALID_FUNDRAISING_CONTROLLER);
        require(isContract(_fundraisingPool), ERROR_INVALID_POOL);
        require(_fundingPeriod > 0, ERROR_INVALID_TIME_PERIOD);
        require(_vestingCliffPeriod > _fundingPeriod, ERROR_INVALID_TIME_PERIOD);
        require(_vestingCompletePeriod > _vestingCliffPeriod, ERROR_INVALID_TIME_PERIOD);
        require(_daiFundingGoal > 0, ERROR_INVALID_DAI_FUNDING_GOAL);
        require(_tapRate > 0, ERROR_INVALID_TAP_RATE);
        require(_percentSupplyOffered > 0, ERROR_INVALID_PERCENT_VALUE);
        require(_percentSupplyOffered < PPM, ERROR_INVALID_PERCENT_VALUE);
        require(_beneficiaryAddress != 0x0, ERROR_INVALID_BENEFICIARY_ADDRESS);
        require(_percentFundingForBenefiriary > 0, ERROR_INVALID_PERCENT_VALUE);
        require(_percentFundingForBenefiriary < PPM, ERROR_INVALID_PERCENT_VALUE);
        // TODO: Perform further validations on the set fundrasing app?

        initialized();

        daiToken = _daiToken;
        _setProjectToken(_projectToken, _projectTokenManager);

        fundraisingController = _fundraisingController;
        fundraisingPool = _fundraisingPool;
        tapRate = _tapRate;

        vestingCliffPeriod = _vestingCliffPeriod;
        vestingCompletePeriod = _vestingCompletePeriod;
        fundingPeriod = _fundingPeriod;

        beneficiaryAddress = _beneficiaryAddress;
        percentFundingForBeneficiary = _percentFundingForBenefiriary;

        daiFundingGoal = _daiFundingGoal;
        percentSupplyOffered = _percentSupplyOffered;

        _calculateExchangeRate();
    }

    /*
     * Public
     */

    function start() public auth(START_ROLE) {
        require(currentSaleState() == SaleState.Pending, ERROR_INVALID_STATE);
        startDate = getTimestamp64();
        emit SaleStarted();
    }

    function buy(uint256 _daiToSpend) public auth(BUY_ROLE) {
        require(currentSaleState() == SaleState.Funding, ERROR_INVALID_STATE);
        require(daiToken.balanceOf(msg.sender) >= _daiToSpend, ERROR_INSUFFICIENT_DAI);
        require(daiToken.allowance(msg.sender, address(this)) >= _daiToSpend, ERROR_INSUFFICIENT_DAI_ALLOWANCE);

        require(daiToken.transferFrom(msg.sender, address(this), _daiToSpend), ERROR_DAI_TRANSFER_REVERTED);

        uint256 tokensToSell = daiToProjectTokens(_daiToSpend);
        projectTokenManager.issue(tokensToSell);
        uint256 purchaseId = projectTokenManager.assignVested(
            msg.sender,
            tokensToSell,
            startDate,
            startDate.add(vestingCliffPeriod),
            startDate.add(vestingCompletePeriod),
            true /* revokable */
        );

        totalDaiRaised = totalDaiRaised.add(_daiToSpend);
        purchases[msg.sender][purchaseId] = _daiToSpend;

        emit TokensPurchased(msg.sender, _daiToSpend, tokensToSell, purchaseId);
    }

    function refund(address _buyer, uint256 _purchaseId) public {
        require(currentSaleState() == SaleState.Refunding, ERROR_INVALID_STATE);

        uint256 daiToRefund = purchases[_buyer][_purchaseId];
        require(daiToRefund > 0, ERROR_NOTHING_TO_REFUND);

        purchases[_buyer][_purchaseId] = 0;
        require(daiToken.transfer(_buyer, daiToRefund), ERROR_DAI_TRANSFER_REVERTED);

        // Note: this assumes that the buyer didn't transfer any of the vested tokens.
        (uint256 tokensSold,,,,,) = projectTokenManager.getVesting(_buyer, _purchaseId);
        projectTokenManager.revokeVesting(_buyer, _purchaseId);
        projectTokenManager.burn(address(projectTokenManager), tokensSold);

        emit TokensRefunded(_buyer, daiToRefund, tokensSold, _purchaseId);
    }

    function close() public {
        require(currentSaleState() == SaleState.GoalReached, ERROR_INVALID_STATE);

        uint256 daiForBeneficiary = totalDaiRaised.mul(percentFundingForBeneficiary).div(PPM);
        require(daiToken.transfer(beneficiaryAddress, daiForBeneficiary), ERROR_DAI_TRANSFER_REVERTED);

        uint256 daiForPool = daiToken.balanceOf(address(this));
        require(daiToken.transfer(fundraisingPool, daiForPool), ERROR_DAI_TRANSFER_REVERTED);

        fundraisingController.addCollateralToken(
            daiToken,
            0,
            0,
            CONNECTOR_WEIGHT_PPM,
            tapRate
        );

        fundraisingInitialized = true;

        emit SaleClosed();
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
        } else if (totalDaiRaised >= daiFundingGoal) {
            if (fundraisingInitialized) {
                return SaleState.Closed;
            } else {
                return SaleState.GoalReached;
            }
        } else if (_timeSinceFundingStarted() < fundingPeriod) {
            return SaleState.Funding;
        } else {
            return SaleState.Refunding;
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
        uint256 connectorWeight = uint256(CONNECTOR_WEIGHT_PPM);
        uint256 exchangeRate = daiFundingGoal.mul(PPM).div(connectorWeight).mul(percentSupplyOffered).div(PPM);
        daiToProjectTokenMultiplier = exchangeRate;
    }

    function _setProjectToken(MiniMeToken _projectToken, TokenManager _projectTokenManager) private {
        require(isContract(_projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        require(_projectToken.controller() != address(projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        projectToken = _projectToken;
        projectTokenManager = _projectTokenManager;
    }
}
