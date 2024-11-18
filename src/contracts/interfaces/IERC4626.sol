// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IKopio} from "interfaces/IKopio.sol";

interface IERC4626 {
    /**
     * @notice The underlying kopio
     */
    function asset() external view returns (IKopio);

    event Issue(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Destroy(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Deposit assets for equivalent amount of shares
     * @param assets Amount of assets to deposit
     * @param receiver Address to send shares to
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @notice Withdraw assets for equivalent amount of shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to send assets to
     * @param owner Address to burn shares from
     * @return shares Amount of shares burned
     * @dev shares are burned from owner, not msg.sender
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function maxDeposit(address) external view returns (uint256);

    function maxMint(address) external view returns (uint256 assets);

    function maxRedeem(address owner) external view returns (uint256 assets);

    function maxWithdraw(address owner) external view returns (uint256 assets);

    /**
     * @notice Mint shares for equivalent amount of assets
     * @param shares Amount of shares to mint
     * @param receiver Address to send shares to
     * @return assets Amount of assets redeemed
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    function previewMint(uint256 shares) external view returns (uint256 assets);

    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Track the underlying amount
     * @return Total supply for the underlying kopio
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to send assets to
     * @param owner Address to burn shares from
     * @return assets Amount of assets redeemed
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}
