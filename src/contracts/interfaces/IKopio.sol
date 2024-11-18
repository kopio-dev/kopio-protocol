// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IAccessControlEnumerable} from "@oz/access/extensions/IAccessControlEnumerable.sol";
import {IERC20Permit} from "kopio/token/IERC20Permit.sol";
import {IERC165} from "vendor/IERC165.sol";

interface IKopio is IERC20Permit, IAccessControlEnumerable, IERC165 {
    event Wrap(address indexed asset, address underlying, address indexed to, uint256 amount);
    event Unwrap(address indexed asset, address underlying, address indexed to, uint256 amount);

    /**
     * @notice Rebase information
     * @param positive supply increasing/reducing rebase
     * @param denominator the denominator for the operator, 1 ether = 1
     */
    struct Rebase {
        uint248 denominator;
        bool positive;
    }

    /**
     * @notice Configuration to allot wrapping an underlying token to a kopio.
     * @param underlying The underlying ERC20.
     * @param underlyingDec Decimals of the token.
     * @param openFee wrap fee from underlying to assets.
     * @param closeFee fee when wrapping from kopio to underlying.
     * @param native Whether native is supported.
     * @param feeRecipient Fee recipient.
     */
    struct Wraps {
        address underlying;
        uint8 underlyingDec;
        uint48 openFee;
        uint40 closeFee;
        bool native;
        address payable feeRecipient;
    }

    function protocol() external view returns (address);
    function share() external view returns (address);

    function rebaseInfo() external view returns (Rebase memory);

    function wraps() external view returns (Wraps memory);

    function isRebased() external view returns (bool);

    /**
     * @notice Perform a rebase by changing the balance denominator and/or the operator
     * @param denominator denominator for the operator, 1 ether = 1
     * @param positive supply increasing/reducing rebase
     * @param afterRebase external call after rebase
     * @dev denominator of 0 or 1e18 cancels the rebase
     */
    function rebase(uint248 denominator, bool positive, bytes calldata afterRebase) external;

    /**
     * @notice Updates ERC20 metadata for the token in case eg. a ticker change
     * @param _name new name for the asset
     * @param _symbol new symbol for the asset
     * @param _version number that must be greater than latest emitted `Initialized` version
     */
    function reinitializeERC20(string memory _name, string memory _symbol, uint8 _version) external;

    /**
     * @notice Mints tokens to an address.
     * @dev Only callable by operator.
     * @dev Internal balances are always unrebased, events emitted are not.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns tokens from an address.
     * @dev Only callable by operator.
     * @dev Internal balances are always unrebased, events emitted are not.
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function pause() external;

    /**
     * @notice  Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function unpause() external;

    /**
     * @notice Deposit underlying tokens to receive equal value of kopio (-fee).
     * @param to address to send the wrapped tokens.
     * @param amount amount to deposit
     */
    function wrap(address to, uint256 amount) external;

    /**
     * @notice Withdraw underlying tokens. (-fee).
     * @param to address receiving the withdrawal.
     * @param amount amount to withdraw
     * @param toNative bool whether to receive underlying as native
     */
    function unwrap(address to, uint256 amount, bool toNative) external;

    /**
     * @notice Sets the fixed share address.
     * @param addr the address of the fixed share.
     */
    function setShare(address addr) external;

    /**
     * @notice enables wraps with native underlying
     * @param enabled enabled (bool).
     */
    function enableNative(bool enabled) external;

    /**
     * @notice Sets fee recipient address
     * @param newRecipient The fee recipient address.
     */
    function setFeeRecipient(address newRecipient) external;

    /**
     * @notice Sets deposit fee
     * @param newOpenFee The open fee (uint48).
     */
    function setOpenFee(uint48 newOpenFee) external;

    /**
     * @notice Sets the fee on unwrap.
     * @param newCloseFee The open fee (uint48).
     */
    function setCloseFee(uint40 newCloseFee) external;

    /**
     * @notice Sets underlying token address (and its decimals)
     * @notice Zero address will disable wraps.
     * @param underlyingAddr The underlying address.
     */
    function setUnderlying(address underlyingAddr) external;
}
