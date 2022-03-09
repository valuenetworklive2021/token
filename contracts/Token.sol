// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Token is ERC20Permit {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SUPPLY = 3500000 ether;
    uint256 public constant MAX_CLAIM = 2432000 ether;
    uint256 public immutable CLAIM_END;

    uint256 public constant FEES = 200; // 2%;
    uint256 public constant FEES_DENOMINATOR = 10000;

    IERC20 public immutable TOKEN;
    address public immutable BURN_ADDRESS;

    uint256 public totalClaimed;

    event TokensClaimed(address user, uint256 amount);

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor()
        ERC20("Value Network Token", "VNTWIN")
        ERC20Permit("Value Network Token")
    {
        TOKEN = IERC20(0xd0f05D3D4e4d1243Ac826d8c6171180c58eaa9BC);
        CLAIM_END = _getNow().add(864000); // 10*24*60*60 = 864000
        BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

        // 3500000-2432000 = 1068000 (max supply - tokens to claim)
        _mint(_msgSender(), MAX_SUPPLY - MAX_CLAIM);
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
        toBurn = (amount * FEES) / FEES_DENOMINATOR;
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

        totalClaimed = totalClaimed.add(amount);
        require(totalClaimed <= MAX_CLAIM, "TRANSACTION_EXCEEDING_MAX_CAP");

        _mint(_msgSender(), amount);
        TOKEN.safeTransferFrom(_msgSender(), BURN_ADDRESS, amount);
        emit TokensClaimed(_msgSender(), amount);
    }

    modifier inClaimPeriod() {
        require(_getNow() < CLAIM_END, "CLAIM_PERIOD_ENDED");
        _;
    }
}
