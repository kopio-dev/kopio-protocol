// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {AccessControlEnumerableUpgradeable} from "@oz-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Role} from "common/Constants.sol";
import {err} from "common/Errors.sol";
import {IKopioIssuer} from "interfaces/IKopioIssuer.sol";
import {IKopioShare} from "interfaces/IKopioShare.sol";
import {ERC4626Upgradeable, IERC4626} from "./ERC4626Upgradeable.sol";
import {IERC165} from "vendor/IERC165.sol";

/* solhint-disable no-empty-blocks */

/**
 * @title kopio share
 * @author the kopio project
 * Pro-rata representation of the underlying asset.
 * Based on ERC-4626 by Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
 *
 * @notice Main purpose of this token is to represent a static amount of the possibly rebased underlying kopio.
 * use-cases are normalized book-keeping, bridging or external integrations.
 *
 * @notice Shares are amounts of this token.
 * @notice Assets are amount of kopios.
 */
contract KopioShare is IKopioShare, ERC4626Upgradeable, AccessControlEnumerableUpgradeable {
    constructor(address _asset) payable ERC4626Upgradeable(_asset) {}

    function initialize(string memory _name, string memory _symbol, address _admin) external initializer {
        // ERC4626
        __ERC4626Upgradeable_init(_name, _symbol);
        _grantRole(Role.DEFAULT_ADMIN, _admin);
        _grantRole(Role.ADMIN, _admin);
        _grantRole(Role.OPERATOR, asset.protocol());

        asset.setShare(address(this));
    }

    /// @inheritdoc IKopioShare
    function reinitializeERC20(
        string memory _name,
        string memory _symbol,
        uint8 _version
    ) external onlyRole(Role.ADMIN) reinitializer(_version) {
        __ERC20Upgradeable_init(_name, _symbol);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerableUpgradeable, IERC165) returns (bool) {
        return
            interfaceId != 0xffffffff &&
            (interfaceId == type(IKopioShare).interfaceId ||
                interfaceId == type(IKopioIssuer).interfaceId ||
                interfaceId == 0x01ffc9a7 ||
                interfaceId == 0x36372b07 ||
                super.supportsInterface(interfaceId));
    }

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        return asset.totalSupply();
    }

    /// @inheritdoc IKopioIssuer
    function convertManyToShares(uint256[] calldata assets) external view returns (uint256[] memory shares) {
        shares = new uint256[](assets.length);
        for (uint256 i; i < assets.length; ) {
            shares[i] = super.convertToShares(assets[i]);
            unchecked {
                ++i;
            }
        }
        return shares;
    }

    /// @inheritdoc IKopioIssuer
    function convertManyToAssets(uint256[] calldata shares) external view returns (uint256[] memory assets) {
        assets = new uint256[](shares.length);
        for (uint256 i; i < shares.length; ) {
            assets[i] = super.convertToAssets(shares[i]);
            unchecked {
                ++i;
            }
        }
        return assets;
    }

    /// @inheritdoc IKopioShare
    function issue(uint256 assets, address to) public returns (uint256 shares) {
        _onlyOperator();
        shares = _issue(assets, to);
    }

    /// @inheritdoc IKopioShare
    function destroy(uint256 _assets, address _from) public returns (uint256 shares) {
        _onlyOperator();
        shares = _destroy(_assets, _from);
    }

    /// @inheritdoc IKopioShare
    function wrap(uint256 assets) external {
        _onlyOperatorOrAsset();
        // Mint share shares to the asset contract
        _mint(address(asset), convertToShares(assets));
    }

    /// @inheritdoc IKopioShare
    function unwrap(uint256 assets) external {
        _onlyOperatorOrAsset();
        // Burn share shares from the asset contract
        _burn(address(asset), convertToShares(assets));
    }
    function convertToAssets(
        uint256 shares
    ) public view virtual override(ERC4626Upgradeable, IKopioShare) returns (uint256 assets) {
        return super.convertToAssets(shares);
    }

    /// @inheritdoc IERC4626
    function convertToShares(
        uint256 assets
    ) public view virtual override(ERC4626Upgradeable, IKopioShare) returns (uint256 shares) {
        return super.convertToShares(assets);
    }

    /// @notice No support for direct interactions yet
    function mint(uint256, address) public pure override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        revert err.MINT_NOT_SUPPORTED();
    }

    /// @notice No support for direct interactions yet
    function deposit(uint256, address) public pure override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        revert err.DEPOSIT_NOT_SUPPORTED();
    }

    /// @notice No support for direct interactions yet
    function withdraw(uint256, address, address) public pure override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        revert err.WITHDRAW_NOT_SUPPORTED();
    }

    /// @notice No support for direct interactions yet
    function redeem(uint256, address, address) public pure override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        revert err.REDEEM_NOT_SUPPORTED();
    }

    /* -------------------------------------------------------------------------- */
    /*                            INTERNAL HOOKS LOGIC                            */
    /* -------------------------------------------------------------------------- */
    function _onlyOperator() internal view {
        if (!hasRole(Role.OPERATOR, msg.sender)) {
            revert err.SENDER_NOT_OPERATOR(errID(), msg.sender, asset.protocol());
        }
    }

    function _onlyOperatorOrAsset() private view {
        if (msg.sender != address(asset) && !hasRole(Role.OPERATOR, msg.sender)) {
            revert err.INVALID_KOPIO_OPERATOR(assetID(), msg.sender, getRoleMember(Role.OPERATOR, 0));
        }
    }
}
