// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IVesting.sol";

contract Vesting is ReentrancyGuard, IVesting, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice start of vesting period as a timestamp
    uint256 public immutable start;

    /// @notice end of vesting period as a timestamp
    uint256 public immutable end;

    /// @notice cliff duration in seconds
    uint256 public immutable cliffDuration;

    /// @notice amount vested for a beneficiary. Note beneficiary address can not be reused
    mapping(address => uint256) public vestedAmount;

    /// @notice cumulative total of tokens drawn down (and transferred from the deposit account) per beneficiary
    mapping(address => uint256) public totalDrawn;

    /// @notice last drawn down timestamp per beneficiary
    mapping(address => uint256) public lastDrawnAt;

    /// @notice ERC20 token we are vesting
    IERC20 public immutable token;

    /**
     * @notice Construct a new vesting contract
     */
    constructor(address _token) {
        require(_token != address(0), "ZERO_ADDRESS");

        token = IERC20(_token);

        // will be updated before deploying
        start = _getNow();
        end = start + 63072000; // 2*365*24*60*60 = 63072000
        cliffDuration = 2678400; // 31*24*60*60 = 2678400

        predefinedBeneficiaries();
    }

    function predefinedBeneficiaries() internal pure {
        // total 1068000 * 0.98 = 1046640 (-2% fees on load)
        // will be updated before deploying
        // vestedAmount[
        //     0xB32A83EEC46B116C53a957Cb07318310c390125F
        // ] = 100000 ether;
    }

    /**
     * @notice Create new vesting schedules in a batch
     * @notice A transfer is used to bring tokens into the VestingDepositAccount so pre-approval is required
     * @param _beneficiaries array of beneficiaries of the vested tokens
     * @param _amounts array of amount of tokens (in wei)
     * @dev array index of address should be the same as the array index of the amount
     */
    function createVestingSchedules(
        address[] calldata _beneficiaries,
        uint256[] calldata _amounts
    ) external onlyOwner {
        require(
            _beneficiaries.length > 0,
            "VestingContract::createVestingSchedules: Empty Data"
        );
        require(
            _beneficiaries.length == _amounts.length,
            "VestingContract::createVestingSchedules: Array lengths do not match"
        );

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            _createVestingSchedule(_beneficiaries[i], _amounts[i]);
        }
    }

    /**
     * @notice Create a new vesting schedule
     * @notice A transfer is used to bring tokens into the VestingDepositAccount so pre-approval is required
     * @param _beneficiary beneficiary of the vested tokens
     * @param _amount amount of tokens (in wei)
     */
    function createVestingSchedule(address _beneficiary, uint256 _amount)
        external
        onlyOwner
    {
        _createVestingSchedule(_beneficiary, _amount);
    }

    /**
     * @notice Draws down any vested tokens due
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     */
    function drawDown() external nonReentrant returns (bool) {
        return _drawDown(msg.sender);
    }

    // Accessors

    /**
     * @notice Vested token balance for a beneficiary
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     * @return _tokenBalance total balance proxied via the ERC20 token
     */
    function tokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Vesting schedule and associated data for a beneficiary
     * @dev Must be called directly by the beneficiary assigned the tokens in the schedule
     * @return _amount
     * @return _totalDrawn
     * @return _lastDrawnAt
     * @return _remainingBalance
     */
    function vestingScheduleForBeneficiary(address _beneficiary)
        external
        view
        returns (
            uint256 _amount,
            uint256 _totalDrawn,
            uint256 _lastDrawnAt,
            uint256 _remainingBalance
        )
    {
        return (
            vestedAmount[_beneficiary],
            totalDrawn[_beneficiary],
            lastDrawnAt[_beneficiary],
            vestedAmount[_beneficiary].sub(totalDrawn[_beneficiary])
        );
    }

    /**
     * @notice Draw down amount currently available (based on the timestamp)
     * @param _beneficiary beneficiary of the vested tokens
     * @return _amount tokens due from vesting schedule
     */
    function availableDrawDownAmount(address _beneficiary)
        external
        view
        returns (uint256 _amount)
    {
        return _availableDrawDownAmount(_beneficiary);
    }

    /**
     * @notice Balance remaining in vesting schedule
     * @param _beneficiary beneficiary of the vested tokens
     * @return _remainingBalance tokens still due (and currently locked) from vesting schedule
     */
    function remainingBalance(address _beneficiary)
        external
        view
        returns (uint256)
    {
        return vestedAmount[_beneficiary].sub(totalDrawn[_beneficiary]);
    }

    // Internal

    function _createVestingSchedule(address _beneficiary, uint256 _amount)
        internal
    {
        require(
            _beneficiary != address(0),
            "VestingContract::createVestingSchedule: Beneficiary cannot be empty"
        );
        require(
            _amount > 0,
            "VestingContract::createVestingSchedule: Amount cannot be empty"
        );

        // Ensure one per address
        require(
            vestedAmount[_beneficiary] == 0,
            "VestingContract::createVestingSchedule: Schedule already in flight"
        );

        uint256 initialBalance = tokenBalance();

        // Vest the tokens into the deposit account and delegate to the beneficiary
        token.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 finalBalance = tokenBalance();

        vestedAmount[_beneficiary] = finalBalance.sub(initialBalance);

        emit ScheduleCreated(_beneficiary);
    }

    function _drawDown(address _beneficiary) internal returns (bool) {
        require(
            vestedAmount[_beneficiary] > 0,
            "VestingContract::_drawDown: There is no schedule currently in flight"
        );

        uint256 amount = _availableDrawDownAmount(_beneficiary);
        require(
            amount > 0,
            "VestingContract::_drawDown: No allowance left to withdraw"
        );

        // Safety measure
        if (totalDrawn[_beneficiary].add(amount) > vestedAmount[_beneficiary]) {
            amount = vestedAmount[_beneficiary].sub(totalDrawn[_beneficiary]);
        }

        // Increase total drawn amount
        totalDrawn[_beneficiary] = totalDrawn[_beneficiary].add(amount);

        // Update last drawn to now
        lastDrawnAt[_beneficiary] = _getNow();

        // Issue tokens to beneficiary
        token.safeTransfer(_beneficiary, amount);
        emit DrawDown(_beneficiary, amount);

        return true;
    }

    function _getNow() internal view returns (uint256) {
        return block.timestamp;
    }

    function _availableDrawDownAmount(address _beneficiary)
        internal
        view
        returns (uint256)
    {
        // Cliff Period
        if (_getNow() <= start.add(cliffDuration)) {
            // the cliff period has not ended, no tokens to draw down
            return 0;
        }

        // Schedule complete
        if (_getNow() > end) {
            return vestedAmount[_beneficiary].sub(totalDrawn[_beneficiary]);
        }

        // Schedule is active

        // Work out when the last invocation was
        uint256 timeLastDrawnOrStart = lastDrawnAt[_beneficiary] == 0
            ? start
            : lastDrawnAt[_beneficiary];

        // Find out how much time has past since last invocation
        uint256 timePassedSinceLastInvocation = _getNow().sub(
            timeLastDrawnOrStart
        );

        // Work out how many due tokens - time passed * rate per second
        uint256 drawDownRate = vestedAmount[_beneficiary].div(end.sub(start));
        return timePassedSinceLastInvocation.mul(drawDownRate);
    }
}
