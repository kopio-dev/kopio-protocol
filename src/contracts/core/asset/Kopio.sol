// solhint-disable no-empty-blocks
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {AccessControlEnumerableUpgradeable} from "@oz-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@oz-upgradeable/utils/PausableUpgradeable.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";

import {ERC20Upgradeable, ERC20Base} from "kopio/token/ERC20Upgradeable.sol";
import {SafeTransfer, IERC20} from "kopio/token/SafeTransfer.sol";

import {Revert} from "kopio/utils/Funcs.sol";

import {Percents, Role} from "common/Constants.sol";
import {err} from "common/Errors.sol";
import {IKopioShare} from "interfaces/IKopioShare.sol";
import {IKopio, IERC165} from "interfaces/IKopio.sol";
import {Rebaser} from "asset/Rebaser.sol";

/**
 * @title kopio
 * @author the kopio project
 * @notice kopio is a rebasing ERC20 paired to a fixed share.
 * @notice it also wraps an underlying when available.
 */
contract Kopio is ERC20Upgradeable, AccessControlEnumerableUpgradeable, PausableUpgradeable, IKopio {
    constructor() {
        _disableInitializers();
    }

    using SafeTransfer for IERC20;
    using SafeTransfer for address payable;
    using Rebaser for uint256;
    using PercentageMath for uint256;

    Rebase private rebasing;
    bool public isRebased;
    address public protocol;
    address public share;
    Wraps private _wrap;

    function initialize(
        string memory _name,
        string memory _symbol,
        address owner,
        address _protocol,
        address underlying,
        address recipient,
        uint48 openFee,
        uint40 closeFee
    ) external initializer {
        // SetupERC20
        __ERC20Upgradeable_init(_name, _symbol);

        // Setup pausable
        __Pausable_init();

        // Setup the protocol
        _grantRole(Role.OPERATOR, (protocol = _protocol));

        // Setup the state
        _grantRole(Role.ADMIN, msg.sender);
        setUnderlying(underlying);
        setFeeRecipient(recipient);
        setOpenFee(openFee);
        setCloseFee(closeFee);

        _revokeRole(Role.ADMIN, msg.sender);

        // Setup the admin
        _grantRole(Role.DEFAULT_ADMIN, owner);
        _grantRole(Role.ADMIN, owner);
    }

    /// @inheritdoc IKopio
    function setShare(address addr) external {
        if (addr == address(0)) revert err.ZERO_ADDRESS();

        // allows easy initialization from share itself
        if (share != address(0)) _checkRole(Role.ADMIN);

        share = addr;
        _grantRole(Role.OPERATOR, addr);
    }

    /// @inheritdoc IKopio
    function setUnderlying(address underlyingAddr) public onlyRole(Role.ADMIN) {
        _wrap.underlying = underlyingAddr;
        if (underlyingAddr != address(0)) {
            _wrap.underlyingDec = IERC20(_wrap.underlying).decimals();
        }
    }

    /// @inheritdoc IKopio
    function enableNative(bool enabled) external onlyRole(Role.ADMIN) {
        _wrap.native = enabled;
    }

    /// @inheritdoc IKopio
    function setFeeRecipient(address recipient) public onlyRole(Role.ADMIN) {
        if (recipient == address(0)) revert err.ZERO_ADDRESS();
        _wrap.feeRecipient = payable(recipient);
    }

    /// @inheritdoc IKopio
    function setOpenFee(uint48 openFee) public onlyRole(Role.ADMIN) {
        if (openFee > Percents.HUNDRED) revert err.INVALID_FEE(errID(), openFee, Percents.HUNDRED);
        _wrap.openFee = openFee;
    }

    /// @inheritdoc IKopio
    function setCloseFee(uint40 closeFee) public onlyRole(Role.ADMIN) {
        if (closeFee > Percents.HUNDRED) revert err.INVALID_FEE(errID(), closeFee, Percents.HUNDRED);
        _wrap.closeFee = closeFee;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Read                                    */
    /* -------------------------------------------------------------------------- */

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerableUpgradeable, IERC165) returns (bool) {
        return (interfaceId != 0xffffffff &&
            (interfaceId == type(IKopio).interfaceId ||
                interfaceId == 0x01ffc9a7 ||
                interfaceId == 0x36372b07 ||
                super.supportsInterface(interfaceId)));
    }

    function wraps() external view override returns (Wraps memory) {
        return _wrap;
    }

    /// @inheritdoc IKopio
    function rebaseInfo() external view override returns (Rebase memory) {
        return rebasing;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view override(ERC20Base, IERC20) returns (uint256) {
        return _totalSupply.rebase(rebasing);
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override(ERC20Base, IERC20) returns (uint256) {
        return _balances[account].rebase(rebasing);
    }

    /// @inheritdoc IKopio
    function pause() public onlyRole(Role.ADMIN) {
        _pause();
    }

    /// @inheritdoc IKopio
    function unpause() public onlyRole(Role.ADMIN) {
        _unpause();
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Write                                   */
    /* -------------------------------------------------------------------------- */
    /// @inheritdoc IKopio
    function reinitializeERC20(
        string memory _name,
        string memory _symbol,
        uint8 _version
    ) external onlyRole(Role.ADMIN) reinitializer(_version) {
        __ERC20Upgradeable_init(_name, _symbol);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Restricted                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IKopio
    function rebase(uint248 denominator, bool positive, bytes calldata functionCall) external onlyRole(Role.ADMIN) {
        if (denominator < 1 ether) revert err.INVALID_DENOMINATOR(errID(), denominator, 1 ether);
        if (denominator == 1 ether) {
            isRebased = false;
            rebasing = Rebase(0, false);
        } else {
            isRebased = true;
            rebasing = Rebase(denominator, positive);
        }
        if (functionCall.length != 0) _execute(functionCall);
    }

    /// @inheritdoc IKopio
    function mint(address to, uint256 amount) external onlyRole(Role.OPERATOR) {
        _requireNotPaused();
        _mint(to, amount);
    }

    /// @inheritdoc IKopio
    function burn(address from, uint256 amount) external onlyRole(Role.OPERATOR) {
        _requireNotPaused();
        _burn(from, amount);
    }

    /// @inheritdoc IKopio
    function wrap(address to, uint256 amount) external {
        _requireNotPaused();

        address underlying = _wrap.underlying;
        if (underlying == address(0)) {
            revert err.WRAP_NOT_SUPPORTED();
        }

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        uint256 openFee = _wrap.openFee;
        if (openFee > 0) {
            uint256 fee = amount.percentMul(openFee);
            amount -= fee;
            IERC20(underlying).safeTransfer(address(_wrap.feeRecipient), fee);
        }

        amount = _adjustDecimals(amount, _wrap.underlyingDec, decimals);

        IKopioShare(share).wrap(amount);
        _mint(to, amount);

        emit Wrap(address(this), underlying, to, amount);
    }

    /// @inheritdoc IKopio
    function unwrap(address to, uint256 amount, bool _receiveNative) external {
        _requireNotPaused();

        address underlying = _wrap.underlying;
        if (underlying == address(0)) {
            revert err.WRAP_NOT_SUPPORTED();
        }

        uint256 adjustedAmount = _adjustDecimals(amount, _wrap.underlyingDec, decimals);

        IKopioShare(share).unwrap(adjustedAmount);
        _burn(msg.sender, adjustedAmount);

        bool allowNative = _receiveNative && _wrap.native;

        uint256 closeFee = _wrap.closeFee;
        if (closeFee > 0) {
            uint256 fee = amount.percentMul(closeFee);
            amount -= fee;

            if (!allowNative) {
                IERC20(underlying).safeTransfer(_wrap.feeRecipient, fee);
            } else {
                _wrap.feeRecipient.safeTransferETH(fee);
            }
        }
        if (!allowNative) {
            IERC20(underlying).safeTransfer(to, amount);
        } else {
            payable(to).safeTransferETH(amount);
        }

        emit Unwrap(address(this), underlying, msg.sender, amount);
    }

    receive() external payable {
        _requireNotPaused();
        if (!_wrap.native) revert err.NATIVE_TOKEN_DISABLED(errID());

        uint256 amount = msg.value;
        if (amount == 0) revert err.ZERO_AMOUNT(errID());

        uint256 openFee = _wrap.openFee;
        if (openFee > 0) {
            uint256 fee = amount.percentMul(openFee);
            amount -= fee;
            _wrap.feeRecipient.safeTransferETH(fee);
        }

        IKopioShare(share).wrap(amount);
        _mint(msg.sender, amount);

        emit Wrap(address(this), address(0), msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Internal                                  */
    /* -------------------------------------------------------------------------- */

    function _mint(address to, uint256 amount) internal override {
        super._mint(to, amount.unrebase(rebasing));
    }

    function _burn(address from, uint256 amount) internal override {
        super._burn(from, amount.unrebase(rebasing));
    }

    /// @dev Internal balances are always unrebased, events emitted are not.
    function _transfer(address from, address to, uint256 amount) internal override returns (bool) {
        uint256 bal = balanceOf(from);
        if (amount > bal) revert err.NOT_ENOUGH_BALANCE(from, amount, bal);
        return super._transfer(from, to, amount.unrebase(rebasing));
    }

    function _execute(bytes calldata functionCall) internal {
        (address target, bytes memory callData) = abi.decode(functionCall, (address, bytes));
        (bool success, bytes memory result) = target.call{value: msg.value}(callData);
        if (!success) Revert(result);
    }

    function _adjustDecimals(uint256 amount, uint8 fromDecimal, uint8 toDecimal) internal pure returns (uint256) {
        if (fromDecimal == toDecimal) return amount;
        return
            fromDecimal < toDecimal ? amount * (10 ** (toDecimal - fromDecimal)) : amount / (10 ** (fromDecimal - toDecimal));
    }

    function errID() internal view returns (err.ID memory) {
        return err.ID(symbol, address(this));
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
        _requireNotPaused();
    }
}
