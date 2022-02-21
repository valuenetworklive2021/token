// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Token is ERC20, Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PERCENTAGE_DECIMAL = 10000;

    uint256 public burnRate = 200; // 2%;

    // 3500000-2432000 = 1068000 (total supply - tokens to claim)
    uint256 public initialSupply = 1068000;
    uint256 public maxCap = 3500000;

    uint256 public start;
    address public liquidityPool;
    IERC20 public oldToken;

    event BurnRateUpdate(uint256 burnRate);
    event LiquidityPoolAdded(address liquidityPool);
    event TokensClaimed(address user, uint256 amount);

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        oldToken = IERC20(0xd0f05D3D4e4d1243Ac826d8c6171180c58eaa9BC);
        _mint(_msgSender(), initialSupply * 10**(decimals()));
    }

    /**
     * @dev Sets burn rate of token.
     * @param _burnRate new burn rate to set
     *
     * Requirements:
     *
     * - `_burnRate` should be less than 10000.
     */
    function setBurnRate(uint256 _burnRate) external onlyOwner {
        require(_burnRate <= 10000, "Token:setBurnRate:: INVALID_BURN_RATE");

        burnRate = _burnRate;

        emit BurnRateUpdate(burnRate);
    }

    /**
     * @dev Sets liqudity pool of token.
     * @param _liquidityPool address of the pool created
     */
    function setLiquidityPoolAddress(address _liquidityPool)
        external
        onlyOwner
    {
        require(
            _liquidityPool != address(0),
            "Token:setLiquidityPoolAddress:: ZERO_ADDRESS"
        );

        liquidityPool = _liquidityPool;

        emit LiquidityPoolAdded(_liquidityPool);
    }

    /**
     * @dev pauses contract.
     *
     * Requirements:
     *
     * - `onlyOwner` should be true.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpauses contract.
     *
     * Requirements:
     *
     * - `onlyOwner` should be true.
     */
    function unpause() external onlyOwner {
        _unpause();
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
        whenNotPaused
        returns (bool)
    {
        uint256 toBurn = _toBurn(amount);

        _transfer(_msgSender(), recipient, amount.sub(toBurn));
        _investAndBurn(_msgSender(), toBurn);
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
    ) public override whenNotPaused returns (bool) {
        uint256 toBurn = _toBurn(amount);

        uint256 currentAllowance = allowance(sender, _msgSender());
        require(
            currentAllowance >= amount,
            "Token:transferFrom:: TRANSFER AMOUNT EXCEEDS ALLOWANCE"
        );
        _approve(sender, _msgSender(), currentAllowance.sub(amount));

        _transfer(sender, recipient, amount.sub(toBurn));
        _investAndBurn(sender, toBurn);
        return true;
    }

    /**
     * @dev Returns amount to transfer after burning fees.
     * @param amount amount of tokens to transfer
     */
    function _toBurn(uint256 amount) internal view returns (uint256 toBurn) {
        toBurn = (amount * burnRate) / PERCENTAGE_DECIMAL;
    }

    /**
     * @dev Burns and sends a portion of token transferred to liquidity pool if already created.
     * @param _from amount of tokens to transfer
     * @param _amount amount of tokens to transfer
     */
    function _investAndBurn(address _from, uint256 _amount) internal {
        uint256 toBurn = _amount;

        if (liquidityPool != address(0)) {
            toBurn = _amount / 2;
            _transfer(_from, liquidityPool, _amount.sub(toBurn));
        }

        _burn(_from, toBurn);
    }

    /**
     * @dev Allows users to claim new tokens by transferring old tokens to owner's address.
     * @dev In order to transfer the tokens, the old tokens must be approved to the contract.
     * @param amount amount of tokens to exchange
     */
    function claim(uint256 amount) external {
        require(amount != 0, "ZERO_AMOUNT");
        require(totalSupply() <= maxCap, "TRANSACTION_EXCEEDING_MAX_CAP");

        _mint(_msgSender(), amount);

        oldToken.safeTransferFrom(_msgSender(), owner(), amount);
        emit TokensClaimed(_msgSender(), amount);
    }
}
