// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransfer} from "kopio/token/SafeTransfer.sol";
import {ERC20Upgradeable} from "kopio/token/ERC20Upgradeable.sol";

import {FixedPointMath} from "vendor/FixedPointMath.sol";
import {id, err} from "common/Errors.sol";
import {IKopio, IERC4626} from "interfaces/IERC4626.sol";

/* solhint-disable func-name-mixedcase */
/* solhint-disable no-empty-blocks */
/* solhint-disable func-visibility */

/// @notice Minimal ERC4626 tokenized Vault implementation.
/// @notice kopio:issue/destroy functions are called on mints/burns in the protocol
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
/// @author kopio (https://kopio.io)
abstract contract ERC4626Upgradeable is IERC4626, ERC20Upgradeable {
    using SafeTransfer for IKopio;
    using FixedPointMath for uint256;

    IKopio public immutable asset;

    constructor(address _asset) payable {
        asset = IKopio(_asset);
        decimals = asset.decimals();
        _disableInitializers();
    }

    /**
     * @notice Initializes the ERC4626.
     * @param _name Name of the share token
     * @param _symbol Symbol of the share token
     */
    function __ERC4626Upgradeable_init(string memory _name, string memory _symbol) internal onlyInitializing {
        __ERC20Upgradeable_init(_name, _symbol);
    }

    /* -------------------------------------------------------------------------- */
    /*                                Issue & Destroy                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice When new assets are minted:
     * Issues the equivalent amount of shares to protocol
     * Issues the equivalent amount of assets to user
     */
    function _issue(uint256 assets, address to) internal virtual returns (uint256 shares) {
        shares = convertToShares(assets);

        // Mint shares to protocol
        _mint(asset.protocol(), shares);
        // Mint assets to receiver
        asset.mint(to, assets);

        emit Issue(msg.sender, to, assets, shares);

        _afterDeposit(assets, shares);
    }

    /**
     * @notice When new assets are burned:
     * Destroys the equivalent amount of shares from protocol
     * Destroys the equivalent amount of assets from user
     */
    function _destroy(uint256 assets, address from) internal virtual returns (uint256 shares) {
        shares = convertToShares(assets);

        _beforeWithdraw(assets, shares);

        // Burn shares from protocol
        _burn(asset.protocol(), shares);
        // Burn assets from user
        asset.burn(from, assets);

        emit Destroy(msg.sender, from, from, assets, shares);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Accounting Logic                              */
    /* -------------------------------------------------------------------------- */

    function totalAssets() public view virtual returns (uint256);

    function convertToShares(uint256 assets) public view virtual override returns (uint256 shares) {
        uint256 supply = _totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        shares = supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
        if (shares == 0) revert err.ZERO_SHARES_FROM_ASSETS(assetID(), assets, errID());
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        uint256 supply = _totalSupply; // Saves an extra SLOAD if _totalSupply is non-zero.

        assets = supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
        if (assets == 0) revert err.ZERO_ASSETS_FROM_SHARES(errID(), shares, assetID());
    }

    /// @return shares for amount of @param assets
    function previewIssue(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    /// @return shares for amount of @param assets
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    /// @return assets for amount of @param shares
    function previewDestroy(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    /// @return assets for amount of @param shares
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    /// @return assets for amount of @param shares
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = _totalSupply; // Saves an extra SLOAD if _totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    /// @return shares for amount of @param assets
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = _totalSupply; // Saves an extra SLOAD if _totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    /* -------------------------------------------------------------------------- */
    /*                       DEPOSIT/WITHDRAWAL LIMIT VIEWS                       */
    /* -------------------------------------------------------------------------- */

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxIssue(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxDestroy(address owner) public view virtual returns (uint256) {
        return convertToAssets(_balances[owner]);
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return convertToAssets(_balances[owner]);
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return _balances[owner];
    }

    /* -------------------------------------------------------------------------- */
    /*                               EXTERNAL USE                                 */
    /* -------------------------------------------------------------------------- */

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        shares = previewDeposit(assets);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _afterDeposit(assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = _allowances[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                _allowances[owner][msg.sender] = allowed - shares;
            }
        }

        _beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _afterDeposit(assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = _allowances[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                _allowances[owner][msg.sender] = allowed - shares;
            }
        }
        assets = previewRedeem(shares);

        _beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /* -------------------------------------------------------------------------- */
    /*                            INTERNAL HOOKS LOGIC                            */
    /* -------------------------------------------------------------------------- */

    function errID() internal view returns (err.ID memory) {
        return err.ID(symbol, address(this));
    }

    function assetID() internal view returns (err.ID memory) {
        return id(address(asset));
    }

    function _beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

    function _afterDeposit(uint256 assets, uint256 shares) internal virtual {}
}
