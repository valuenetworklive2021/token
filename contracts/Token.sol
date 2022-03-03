// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Token is ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PERCENTAGE_DECIMAL = 10000;
    uint256 public constant COMMISSION_PERCENTAGE = 200; // 2%;
    uint256 public constant THREE_WEEK_IN_SECONDS = 1814400; // 3*7*24*60*60;

    address public constant DEATH_ADDRESS =
        address(0x000000000000000000000000000000000000dEaD);

    // 3500000-2432000 = 1068000 (total supply - tokens to claim)
    uint256 public constant initialSupply = 1068000;
    uint256 public constant maxCap = 3500000;

    uint256 public claimPeriodEnd;
    IERC20 public oldToken;

    event TokensClaimed(address user, uint256 amount);

    modifier inClaimPeriod() {
        require(_getNow() < claimPeriodEnd, "CLAIM_PERIOD_ENDED");
        _;
    }

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor() ERC20("Value Network Token", "VNTWIN") {
        oldToken = IERC20(0xd0f05D3D4e4d1243Ac826d8c6171180c58eaa9BC);
        _mint(_msgSender(), initialSupply * 10**(decimals()));

        claimPeriodEnd = _getNow().add(THREE_WEEK_IN_SECONDS);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     * overrided hence cannot be external
     */
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 toBurn = _toBurn(amount);

        _transfer(_msgSender(), recipient, amount.sub(toBurn));
        _burn(_msgSender(), toBurn);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     * overrided hence cannot be external
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 toBurn = _toBurn(amount);

        _spendAllowance(sender, _msgSender(), amount);
        _transfer(sender, recipient, amount.sub(toBurn));
        _burn(sender, toBurn);
        return true;
    }

    /**
     * @dev Returns amount to transfer after burning fees.
     * @param amount amount of tokens to transfer
     */
    function _toBurn(uint256 amount) internal pure returns (uint256 toBurn) {
        toBurn = (amount * COMMISSION_PERCENTAGE) / PERCENTAGE_DECIMAL;
    }

    function _getNow() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Allows users to claim new tokens by transferring old tokens to owner's address.
     * @dev In order to transfer the tokens, the old tokens must be approved to the contract.
     * @param amount amount of tokens to exchange
     */
    function claim(uint256 amount) external inClaimPeriod {
        require(amount != 0, "ZERO_AMOUNT");
        require(
            totalSupply().add(amount) <= maxCap,
            "TRANSACTION_EXCEEDING_MAX_CAP"
        );

        _mint(_msgSender(), amount);
        oldToken.safeTransferFrom(_msgSender(), DEATH_ADDRESS, amount);
        emit TokensClaimed(_msgSender(), amount);
    }
}
