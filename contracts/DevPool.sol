// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./IVesting.sol";

contract DevPool is Ownable {
    address[] public approvers;
    uint256 public votes;
    struct Transfer {
        uint256 id;
        uint256 amount;
        address payable to;
        uint256 approvals;
        bool sent;
        IERC20 token;
    }
    Transfer[] public transfers;
    mapping(address => mapping(uint256 => bool)) public approvals;

    IVesting public vesting;

    constructor(
        address[] memory _approvers,
        uint256 _votes,
        address _vesting
    ) {
        approvers = _approvers;
        votes = _votes;
        vesting = IVesting(_vesting);
    }

    function drawdownpool() public onlyOwner {
        vesting.drawDown();
    }

    function getApprovers() external view returns (address[] memory) {
        return approvers;
    }

    function getTransfers(uint256 index)
        external
        view
        returns (Transfer memory)
    {
        return transfers[index];
    }

    function createTransfer(
        uint256 amount,
        IERC20 _token,
        address payable to
    ) external onlyApprover {
        transfers.push(
            Transfer(transfers.length, amount, to, 0, false, _token)
        );
    }

    function approveTransfer(uint256 id) external onlyApprover {
        require(transfers[id].sent == false, "transfer has already been sent");
        require(
            approvals[msg.sender][id] == false,
            "cannot approve transfer twice"
        );

        approvals[msg.sender][id] = true;
        transfers[id].approvals++;

        if (transfers[id].approvals >= votes) {
            transfers[id].sent = true;
            address payable to = transfers[id].to;
            uint256 amount = transfers[id].amount;
            transfers[id].token.transfer(to, amount);
        }
    }

    function getContractTokenBalance(IERC20 _token)
        public
        view
        returns (uint256)
    {
        return _token.balanceOf(address(this));
    }

    modifier onlyApprover() {
        bool allowed = false;
        for (uint256 i = 0; i < approvers.length; i++) {
            if (approvers[i] == msg.sender) {
                allowed = true;
            }
        }
        require(allowed == true, "only approver allowed");
        _;
    }
}
