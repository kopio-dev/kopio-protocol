// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

// solhint-disable-next-line
import {AccessControlEnumerableUpgradeable, AccessControlUpgradeable} from "@oz-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@oz-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20Upgradeable} from "kopio/token/ERC20Upgradeable.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";

import {Role} from "common/Constants.sol";
import {err} from "common/Errors.sol";
import {IONE, IERC165, IKopioIssuer, IVaultExtender} from "interfaces/IONE.sol";
import {IVault} from "interfaces/IVault.sol";
import {IVaultFlashReceiver} from "interfaces/IVaultFlashReceiver.sol";

/**
 * @title ONE
 * @author the kopio project
 * @notice non-rebasing unlike others, it is paired with a vault.
 */
contract ONE is ERC20Upgradeable, IONE, IVaultFlashReceiver, PausableUpgradeable, AccessControlEnumerableUpgradeable, err {
    using SafeTransfer for ERC20Upgradeable;

    address public protocol;
    IVault public vault;

    function initialize(
        string memory name_,
        string memory symbol_,
        address admin_,
        address protocol_,
        address vault_
    ) external initializer {
        if (protocol_.code.length == 0) revert NOT_A_CONTRACT(protocol_);

        __ERC20Upgradeable_init(name_, symbol_);

        // Setup the admin
        _grantRole(Role.DEFAULT_ADMIN, admin_);
        _grantRole(Role.ADMIN, admin_);

        // Setup the protocol
        protocol = protocol_;
        _grantRole(Role.OPERATOR, protocol_);

        // Setup vault
        vault = IVault(vault_);
    }

    modifier onlyContract() {
        if (msg.sender.code.length == 0) revert NOT_A_CONTRACT(msg.sender);
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Writes                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IKopioIssuer
    function issue(uint256 amount, address to) public override onlyRole(Role.OPERATOR) returns (uint256) {
        _mint(to, amount);
        return amount;
    }

    /// @inheritdoc IKopioIssuer
    function destroy(uint256 amount, address from) external onlyRole(Role.OPERATOR) returns (uint256) {
        _burn(from, amount);
        return amount;
    }

    /// @inheritdoc IVaultExtender
    function vaultDeposit(
        address asset,
        uint256 amount,
        address receiver
    ) external returns (uint256 sharesOut, uint256 assetFee) {
        (sharesOut, assetFee) = vault.previewDeposit(asset, amount);
        return vaultMint(asset, sharesOut, receiver);
    }

    /// @inheritdoc IVaultExtender
    function vaultMint(address asset, uint256 shares, address receiver) public returns (uint256 assetsIn, uint256 assetFee) {
        return vault.flash(asset, shares, address(this), abi.encode(_addrOr(receiver, msg.sender)));
    }

    /// @inheritdoc IVaultExtender
    function vaultWithdraw(
        address asset,
        uint256 amount,
        address receiver,
        address owner
    ) external returns (uint256 sharesIn, uint256 assetFee) {
        (sharesIn, assetFee) = vault.withdraw(asset, amount, _addrOr(receiver, owner), address(this));
        _spendAllowance(owner, sharesIn);
        _burn(owner, sharesIn);
    }

    /// @inheritdoc IVaultExtender
    function vaultRedeem(
        address asset,
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assetsOut, uint256 assetFee) {
        _spendAllowance(owner, shares);
        _burn(owner, shares);
        (assetsOut, assetFee) = IVault(vault).redeem(asset, shares, _addrOr(receiver, owner), address(this));
    }

    /// @inheritdoc IVaultExtender
    function maxRedeem(address asset, address owner) external view returns (uint256 sharesIn, uint256 assetFee) {
        (uint256 assetsOut, uint256 fee) = vault.previewRedeem(asset, _balances[owner]);
        uint256 assetLimit = vault.maxWithdraw(asset, address(this));

        if (assetsOut + assetFee > assetLimit) return vault.previewWithdraw(asset, assetLimit);

        return (_balances[owner], fee);
    }

    /// @inheritdoc IVaultExtender
    function deposit(uint256 shares, address receiver) external {
        vault.transferFrom(msg.sender, address(this), shares);
        _mint(_addrOr(receiver, msg.sender), shares);
    }

    /// @inheritdoc IVaultExtender
    function withdraw(uint256 amount, address receiver) external {
        _withdraw(msg.sender, _addrOr(receiver, msg.sender), amount);
    }

    /// @inheritdoc IVaultExtender
    function withdrawFrom(address from, address to, uint256 amount) public {
        _spendAllowance(from, amount);
        _withdraw(from, to, amount);
    }

    /// @inheritdoc IONE
    function pause() public onlyContract onlyRole(Role.ADMIN) {
        super._pause();
    }

    /// @inheritdoc IONE
    function unpause() public onlyContract onlyRole(Role.ADMIN) {
        _unpause();
    }

    function onVaultFlash(Flash calldata flash, bytes memory data) external {
        if (msg.sender != address(vault)) revert INVALID_SENDER(msg.sender, address(vault));

        if (flash.kind == FlashKind.Shares) {
            address receiver = abi.decode(data, (address));
            ERC20Upgradeable(flash.asset).safeTransferFrom(receiver, address(vault), flash.assets);
            return _mint(receiver, flash.shares);
        }

        if (flash.kind == FlashKind.Assets) {
            address owner = abi.decode(data, (address));
            return _burn(owner, flash.shares);
        }

        revert FLASH_KIND_NOT_SUPPORTED(flash.kind);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Views                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IONE
    function exchangeRate() external view returns (uint256) {
        return vault.exchangeRate();
    }

    /// @inheritdoc IKopioIssuer
    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /// @inheritdoc IKopioIssuer
    function convertManyToShares(uint256[] calldata assets) external pure returns (uint256[] calldata shares) {
        return assets;
    }

    /// @inheritdoc IKopioIssuer
    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /// @inheritdoc IKopioIssuer
    function convertManyToAssets(uint256[] calldata shares) external pure returns (uint256[] calldata assets) {
        return shares;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerableUpgradeable, IERC165) returns (bool) {
        return (interfaceId != 0xffffffff &&
            (interfaceId == type(IONE).interfaceId ||
                interfaceId == type(IKopioIssuer).interfaceId ||
                interfaceId == 0x01ffc9a7 ||
                interfaceId == 0x36372b07 ||
                super.supportsInterface(interfaceId)));
    }

    /* -------------------------------------------------------------------------- */
    /*                                  internal                                  */
    /* -------------------------------------------------------------------------- */
    function _addrOr(address a, address b) internal pure returns (address) {
        return a == address(0) ? b : a;
    }

    function _withdraw(address from, address to, uint256 amount) internal {
        _burn(from, amount);
        vault.transfer(to, amount);
    }

    function _spendAllowance(address owner, uint256 amount) internal {
        if (msg.sender != owner) {
            uint256 allowed = _allowances[owner][msg.sender]; // Saves gas for limited approvals.
            if (allowed < amount) revert NO_ALLOWANCE(msg.sender, owner, amount, allowed);
            unchecked {
                if (allowed != type(uint256).max) _allowances[owner][msg.sender] = allowed - amount;
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
        if (paused()) revert err.PAUSED(address(this));
    }
}
