// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IVesting.sol";

contract Vesting is ReentrancyGuard, IVesting, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice start of vesting period as a block number
    uint256 public start;

    /// @notice end of vesting period as a block number
    uint256 public end;

    /// @notice cliff duration in seconds
    uint256 public cliffDuration;

    /// @notice amount vested for a beneficiary. Note beneficiary address can not be reused
    mapping(address => uint256) public vestedAmount;

    /// @notice cumulative total of tokens drawn down (and transferred from the deposit account) per beneficiary
    mapping(address => uint256) public totalDrawn;

    /// @notice last drawn down block per beneficiary
    mapping(address => uint256) public lastDrawnAt;

    /// @notice ERC20 token we are vesting
    IERC20 public token;

    /**
     * @notice Construct a new vesting contract
     */
    constructor(address _token) {
        require(_token != address(0), "ZERO_ADDRESS");

        token = IERC20(_token);

        // will be updated before deploying
        start = 1609459200;
        end = 1704067200;

        cliffDuration = 2678400;
        predefinedBeneficiaries();
    }

    function predefinedBeneficiaries() internal pure returns (bool) {
        // will be updated before deploying
        // vestedAmount[
        //     0xB32A83EEC46B116C53a957Cb07318310c390125F
        // ] = 1000000000000000000000000;
        return true;
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
    ) external onlyOwner returns (bool) {
        require(
            _beneficiaries.length > 0,
            "VestingContract::createVestingSchedules: Empty Data"
        );
        require(
            _beneficiaries.length == _amounts.length,
            "VestingContract::createVestingSchedules: Array lengths do not match"
        );

        bool result = true;

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];
            uint256 amount = _amounts[i];
            _createVestingSchedule(beneficiary, amount);
        }

        return result;
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
        returns (bool)
    {
        return _createVestingSchedule(_beneficiary, _amount);
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
     * @notice Draw down amount currently available (based on the block number)
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
        returns (bool)
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

        return true;
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

        // Update last drawn to now
        lastDrawnAt[_beneficiary] = _getCurrentBlock();

        // Increase total drawn amount
        totalDrawn[_beneficiary] = totalDrawn[_beneficiary].add(amount);

        // Safety measure - this should never trigger
        require(
            totalDrawn[_beneficiary] <= vestedAmount[_beneficiary],
            "VestingContract::_drawDown: Safety Mechanism - Drawn exceeded Amount Vested"
        );

        // Issue tokens to beneficiary
        token.safeTransfer(_beneficiary, amount);
        emit DrawDown(_beneficiary, amount);

        return true;
    }

    function _getCurrentBlock() internal view returns (uint256) {
        return block.number;
    }

    function _availableDrawDownAmount(address _beneficiary)
        internal
        view
        returns (uint256 _amount)
    {
        // Cliff Period
        if (_getCurrentBlock() <= start.add(cliffDuration)) {
            // the cliff period has not ended, no tokens to draw down
            return 0;
        }

        // Schedule complete
        if (_getCurrentBlock() > end) {
            return vestedAmount[_beneficiary].sub(totalDrawn[_beneficiary]);
        }

        // Schedule is active

        // Work out when the last invocation was
        uint256 blockLastDrawnOrStart = lastDrawnAt[_beneficiary] == 0
            ? start
            : lastDrawnAt[_beneficiary];

        // Find out how many block have been created since last invocation
        uint256 blocksPassedSinceLastInvocation = _getCurrentBlock().sub(
            blockLastDrawnOrStart
        );

        // Work out how many due tokens - blocks created * rate per block
        uint256 drawDownRate = vestedAmount[_beneficiary].div(end.sub(start));
        uint256 amount = blocksPassedSinceLastInvocation.mul(drawDownRate);

        return amount;
    }
}
