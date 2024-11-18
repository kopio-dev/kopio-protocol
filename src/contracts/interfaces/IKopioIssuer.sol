// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title An issuer for kopio
/// @author the kopio project
/// @notice contract that creates/destroys kopios.
/// @dev protocol enforces this implementation on kopios.
interface IKopioIssuer {
    /**
     * @notice Mints @param assets of kopio for @param to,
     * @notice Mints relative amount of fixed @return shares.
     */
    function issue(uint256 assets, address to) external returns (uint256 shares);

    /**
     * @notice Burns @param assets of kopio from @param from,
     * @notice Burns relative amount of fixed @return shares.
     */
    function destroy(uint256 assets, address from) external returns (uint256 shares);

    /**
     * @notice Preview conversion from kopio amount: @param assets to matching fixed amount: @return shares
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Preview conversion from fixed amount: @param shares to matching kopio amount: @return assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Preview conversion from fixed amounts: @param shares to matching amounts of kopios: @return assets
     */
    function convertManyToAssets(uint256[] calldata shares) external view returns (uint256[] memory assets);

    /**
     * @notice Preview conversion from kopio amounts: @param assets to matching fixed amount: @return shares
     */
    function convertManyToShares(uint256[] calldata assets) external view returns (uint256[] memory shares);
}
