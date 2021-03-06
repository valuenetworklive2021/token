// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IVesting {
    event ScheduleCreated(address indexed _beneficiary);

    /// @notice event emitted when a successful drawn down of vesting tokens is made
    event DrawDown(address indexed _beneficiary, uint256 indexed _amount);

    function createVestingSchedules(
        address[] calldata _beneficiaries,
        uint256[] calldata _amounts
    ) external;

    function createVestingSchedule(address _beneficiary, uint256 _amount)
        external;

    function tokenBalance() external view returns (uint256);

    function vestingScheduleForBeneficiary(address _beneficiary)
        external
        view
        returns (
            uint256 _amount,
            uint256 _totalDrawn,
            uint256 _lastDrawnAt,
            uint256 _remainingBalance
        );

    function availableDrawDownAmount(address _beneficiary)
        external
        view
        returns (uint256 _amount);

    function remainingBalance(address _beneficiary)
        external
        view
        returns (uint256);

    function drawDown() external returns (bool);
}
