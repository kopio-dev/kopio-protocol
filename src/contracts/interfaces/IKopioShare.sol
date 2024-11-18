// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IAccessControlEnumerable} from "@oz/access/extensions/IAccessControlEnumerable.sol";
import {IERC165} from "vendor/IERC165.sol";
import {IERC20Permit} from "kopio/token/IERC20Permit.sol";
import {IERC4626} from "./IERC4626.sol";
import {IKopioIssuer} from "interfaces/IKopioIssuer.sol";

interface IKopioShare is IKopioIssuer, IERC4626, IERC20Permit, IAccessControlEnumerable, IERC165 {
    function issue(uint256 assets, address to) external returns (uint256 shares);

    function destroy(uint256 assets, address from) external returns (uint256 shares);

    function convertToShares(uint256 assets) external view override(IKopioIssuer, IERC4626) returns (uint256 shares);

    function convertToAssets(uint256 shares) external view override(IKopioIssuer, IERC4626) returns (uint256 assets);

    function reinitializeERC20(string memory _name, string memory _symbol, uint8 _version) external;

    /**
     * @notice Mints shares to asset contract.
     * @param assets amount of assets.
     */
    function wrap(uint256 assets) external;

    /**
     * @notice Burns shares from the asset contract.
     * @param assets amount of assets.
     */
    function unwrap(uint256 assets) external;
}
