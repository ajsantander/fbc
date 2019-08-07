pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";

import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/math/SafeMath64.sol";

import "@aragon/os/contracts/lib/token/ERC20.sol";
import "@aragon/apps-shared-minime/contracts/MiniMeToken.sol";
import "@aragon/apps-token-manager/contracts/TokenManager.sol";

import "@ablack/controller-aragon-fundraising/contracts/AragonFundraisingController.sol";
import "@ablack/fundraising-module-pool/contracts/Pool.sol";


contract Presale is AragonApp {
    using SafeMath for uint256;
    using SafeMath64 for uint64;

    /*
     * Events
     */

    event SaleStarted();
    event SaleClosed();
    event TokensPurchased(address indexed buyer, uint256 daiSpent, uint256 tokensPurchased, uint256 purchaseId);
    event TokensRefunded(address indexed buyer, uint256 daiRefunded, uint256 tokensBurned, uint256 purchaseId);

    /*
     * Errors
     */

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
    string private constant ERROR_EXCEEDS_FUNDING_GOAL           = "PRESALE_EXCEEDS_FUNDING_GOAL";

    /*
     * Roles
     */

    bytes32 public constant START_ROLE = keccak256("START_ROLE");
    bytes32 public constant BUY_ROLE   = keccak256("BUY_ROLE");

    /*
     * Properties
     */

    // Token that will be accepted as payment for
    // purchasing project tokens.
    ERC20 public daiToken;

    // Token that is being offered for purchase in the sale.
    MiniMeToken public projectToken;
    TokenManager public projectTokenManager;

    // Funding goal and total dai raised in the sale.
    // Note: no further purchases will be allowed after daiFundingGoal is reached.
    uint256 public daiFundingGoal;
    uint256 public totalDaiRaised;

    // The Fundraising controller where collateral tokens will be added
    // to, once this sale is closed.
    AragonFundraisingController fundraisingController;
    uint256 public tapRate;
    uint256 public percentSupplyOffered; // Represented in PPM, see below
    bool private fundraisingInitialized;

    // Once the sale is closed, totalDaiRaised is split according to
    // percentFundingForBeneficiary, between beneficiaryAddress and fundraisingPool.
    Pool public fundraisingPool;
    address public beneficiaryAddress;
    uint256 public percentFundingForBeneficiary; // Represented in PPM, see below

    // Date when the sale is started and its state is Funding.
    uint64 public startDate;

    // Vesting parameters.
    // Note: startDate also represents the starting date for all vested project tokens.
    uint64 public vestingCliffPeriod;
    uint64 public vestingCompletePeriod;

    // Period after startDate, in which the sale is Funding and accepts contributions.
    // If the daiFundingGoal is not reached within it, the sale cannot be Closed
    // and the state switches to Refunding, allowing dai refunds.
    uint64 public fundingPeriod;

    // Number of project tokens that will be sold for each dai.
    // Calculated after initialization from the values CONNECTOR_WEIGHT_PPM and percentSupplyOffered.
    uint256 public daiToProjectTokenExchangeRate;

    // Percentages are represented in the PPM range (Parts per Million) [0, 1000000]
    // 25% => 0.25 * 1e6
    // 50% => 0.50 * 1e6
    uint256 public constant PPM = 1000000;

    // Used to calculate daiToProjectTokenExchangeRate.
    uint256 public constant CONNECTOR_WEIGHT_PPM = 100000; // 10%

    // Keeps track of how much dai is spent, per purchase, per buyer.
    // This is used when refunding purchases.
    mapping(address => mapping(uint256 => uint256)) public purchases;
    /*      |                  |          |
     *      |                  |          daiSpent
     *      |                  purchaseId
     *      buyer
     */

    // No state variable keeps track of the current state, but is rather
    // calculated from other variables. See: currentSaleState().
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

    /**
    * @notice Initialize Presale app with `_daiToken` to be used for purchasing `_projectToken`, controlled by `_projectTokenManager`. Project tokens are provided in vested form using `_vestingCliffPeriod` and `_vestingCompletePeriod`. The Presale accepts dai until `_daiFundingGoal` is reached. `percentSupplyOffered` is used to calculate the dai to project token exchange rate. The presale allows project token purchases for `_fundingPeriod` after the sale is started. If the funding goal is reached, part of the raised funds are sent to `_fundraisingPool`, associated with a Fundraising app's `_fundraisingController`. The `tapRate` is used when the sale reaches the funding goal and the raised funds are set as collateral in the Fundraising app. The raised funds that are not sent to the fundraising pool are sent to `_beneficiaryAddress` according to the ratio specified in `_percentFundingForBenefiriary`.
    * @param _daiToken ERC20 Token accepted for purchasing project tokens.
    * @param _projectToken MiniMeToken project tokens being offered for sale in vested form.
    * @param _projectTokenManager TokenManager Token manager in control of the offered project tokens.
    * @param _vestingCliffPeriod uint64 Cliff period used for vested project tokens.
    * @param _vestingCompletePeriod uint64 Complete period used for vested project tokens.
    * @param _daiFundingGoal uint256 Target dai funding goal.
    * @param _percentSupplyOffered uin256 Percent of the total supply of project tokens that will be offered in this sale and in further fundraising stages.
    * @param _fundingPeriod uint64 The period within which this sale accepts project token purchases.
    * @param _fundraisingPool Pool The fundraising pool associated with the Fundraising app where part of the raised dai tokens will be sent to, if this sale is succesful.
    * @param _fundraisingController AragonFundraisingController The Fundraising app controller that will be initialized if this sale is successful.
    * @param _tapRate uint256 The tap rate for the raised dai tokens that will be used in the Fundraising app.
    * @param _beneficiaryAddress address The address to which part of the raised dai tokens will be sent to, if this sale is successful.
    * @param _percentFundingForBenefiriary uint256 The percentage of the raised dai tokens that will be sent to the beneficiary address, instead of the fundraising pool, when this sale is closed.
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
        Pool _fundraisingPool,
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
        // TODO: Perform further validations on the set fundrasing app? Eg. Verify if the provided pool is controlled by the Fundraising controller?

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

    /**
    * @notice Starts the sale, changing its state to Funding. After the sale is started contributors will be able to purchase project tokens.
    */
    function start() public auth(START_ROLE) {
        require(currentSaleState() == SaleState.Pending, ERROR_INVALID_STATE);
        startDate = getTimestamp64();
        emit SaleStarted();
    }

    /**
    * @notice Buys project tokens using the provided `_daiToSpend` dai tokens. To calculate how many project tokens will be sold for the provided, dai amount, use daiToProjectTokens(). Each purchase generates a numeric purchaseId (0, 1, 2, etc) for the caller, which can be obtained in the TokensPurchased event emitted, and is required for later refunds.
    * @param _daiToSpend The amount of dai to spend to obtain project tokens.
    */
    function buy(uint256 _daiToSpend) public auth(BUY_ROLE) {
        require(currentSaleState() == SaleState.Funding, ERROR_INVALID_STATE);
        require(daiToken.balanceOf(msg.sender) >= _daiToSpend, ERROR_INSUFFICIENT_DAI);
        require(daiToken.allowance(msg.sender, address(this)) >= _daiToSpend, ERROR_INSUFFICIENT_DAI_ALLOWANCE);
        require(totalDaiRaised.add(_daiToSpend) <= daiFundingGoal, ERROR_EXCEEDS_FUNDING_GOAL);

        // (buyer) ~~~> dai ~~~> (presale)
        require(daiToken.transferFrom(msg.sender, address(this), _daiToSpend), ERROR_DAI_TRANSFER_REVERTED);

        // (mint ✨) ~~~> project tokens ~~~> (buyer)
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

        // Keep track of dai spent in this purchase for later refunding.
        purchases[msg.sender][purchaseId] = _daiToSpend;

        emit TokensPurchased(msg.sender, _daiToSpend, tokensToSell, purchaseId);
    }

    /**
    * @notice Refunds a purchase made by `_buyer`, with id `_purchaseId`. Each purchase has a purchase id, and needs to be refunded separately.
    * @param _buyer address The buyer address to refund.
    * @param _purchaseId uint256 The purchase id to refund.
    */
    function refund(address _buyer, uint256 _purchaseId) public {
        require(currentSaleState() == SaleState.Refunding, ERROR_INVALID_STATE);

        // Recall how much dai to refund for this purchase.
        uint256 daiToRefund = purchases[_buyer][_purchaseId];
        require(daiToRefund > 0, ERROR_NOTHING_TO_REFUND);
        purchases[_buyer][_purchaseId] = 0;

        // (presale) ~~~> dai ~~~> (buyer)
        require(daiToken.transfer(_buyer, daiToRefund), ERROR_DAI_TRANSFER_REVERTED);

        // (buyer) ~~~> project tokens ~~~> (Token manager)
        // Note: this assumes that the buyer didn't transfer any of the vested tokens.
        // The assumption can be made considering the imposed restriction of fundingPeriod < vestingCliffPeriod < vestingCompletePeriod.
        (uint256 tokensSold,,,,,) = projectTokenManager.getVesting(_buyer, _purchaseId);
        projectTokenManager.revokeVesting(_buyer, _purchaseId);

        // (Token manager) ~~~> project tokens ~~~> (burn 💥)
        projectTokenManager.burn(address(projectTokenManager), tokensSold);

        emit TokensRefunded(_buyer, daiToRefund, tokensSold, _purchaseId);
    }

    /**
    * @notice Closes a sale that has reached the funding goal, sending raised funds to the fundraising pool and the beneficiary address, and initializes the Fundraising app by adding the raised funds as collateral tokens.
    */
    function close() public {
        require(currentSaleState() == SaleState.GoalReached, ERROR_INVALID_STATE);

        // (presale) ~~~> dai ~~~> (beneficiary)
        uint256 daiForBeneficiary = totalDaiRaised.mul(percentFundingForBeneficiary).div(PPM);
        require(daiToken.transfer(beneficiaryAddress, daiForBeneficiary), ERROR_DAI_TRANSFER_REVERTED);

        // (presale) ~~~> dai ~~~> (pool)
        uint256 daiForPool = daiToken.balanceOf(address(this));
        require(daiToken.transfer(fundraisingPool, daiForPool), ERROR_DAI_TRANSFER_REVERTED);

        // Initialize Fundraising app.
        fundraisingController.addCollateralToken(
            daiToken,
            0,
            0,
            uint32(CONNECTOR_WEIGHT_PPM),
            tapRate
        );
        fundraisingInitialized = true;

        emit SaleClosed();
    }

    /*
     * Getters
     */

    /**
    * @notice Calculates the number of project tokens that would be obtained for `_daiAmount` dai tokens.
    * @param _daiAmount uint256 The amount of dai tokens to be converted into project tokens.
    */
    function daiToProjectTokens(uint256 _daiAmount) public view returns (uint256) {
        return _daiAmount.mul(daiToProjectTokenExchangeRate);
    }

    /**
    * @notice Calculates the current state of the sale.
    */
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
        uint256 exchangeRate = daiFundingGoal.mul(PPM).div(CONNECTOR_WEIGHT_PPM).mul(percentSupplyOffered).div(PPM);
        daiToProjectTokenExchangeRate = exchangeRate;
    }

    function _setProjectToken(MiniMeToken _projectToken, TokenManager _projectTokenManager) private {
        require(isContract(_projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        require(_projectToken.controller() != address(projectTokenManager), ERROR_INVALID_TOKEN_CONTROLLER);
        projectToken = _projectToken;
        projectTokenManager = _projectTokenManager;
    }
}
