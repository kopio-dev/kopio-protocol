// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IVaultExtender {
    event Deposit(address indexed _from, address indexed _to, uint256 _amount);
    event Withdraw(address indexed _from, address indexed _to, uint256 _amount);

    /**
     * @notice Mint shares from exact assets.
     * @param _assetAddr Supported vault asset address
     * @param _assets Amount to deposit
     * @param _receiver Receives the shares
     * @return sharesOut Amount of shares minted
     * @return assetFee Asset fee taken
     */
    function vaultDeposit(
        address _assetAddr,
        uint256 _assets,
        address _receiver
    ) external returns (uint256 sharesOut, uint256 assetFee);

    /**
     * @notice Mint exact shares from assets.
     * @param _assetAddr Supported vault asset
     * @param _receiver Receives the shares
     * @param _shares Amount of shares to receive
     * @return assetsIn Amount of assets for `_shares`
     * @return assetFee Amount of `_assetAddr` vault took as fee
     */
    function vaultMint(
        address _assetAddr,
        uint256 _shares,
        address _receiver
    ) external returns (uint256 assetsIn, uint256 assetFee);

    /**
     * @notice Withdraw exact amount of assets for shares.
     * @param _assetAddr Supported vault asset
     * @param _assets Exact assets to withdraw
     * @param _receiver Receives the assets
     * @param _owner Owner of shares
     * @return sharesIn Amount of shares burned
     * @return assetFee Asset fee taken
     */
    function vaultWithdraw(
        address _assetAddr,
        uint256 _assets,
        address _receiver,
        address _owner
    ) external returns (uint256 sharesIn, uint256 assetFee);

    /**
     * @notice Withdraw amount of assets for exact shares.
     * @param _assetAddr Supported vault asset
     * @param _shares Exact shares to burn
     * @param _receiver  Receives the assets
     * @param _owner Owner of shares
     * @return assetsOut Amount of assets sent
     * @return assetFee Asset fee taken
     */
    function vaultRedeem(
        address _assetAddr,
        uint256 _shares,
        address _receiver,
        address _owner
    ) external returns (uint256 assetsOut, uint256 assetFee);

    /**
     * @notice Max redeem of shares for `owner`.
     * @param assetAddr Withdraw asset
     * @param owner Owner of the shares.
     * @return max Maximum shares redeemable.
     * @return fee Asset fee for the redeem.
     */
    function maxRedeem(address assetAddr, address owner) external view returns (uint256 max, uint256 fee);

    /**
     * @notice Deposit vault shares for extended share.
     * @param _shares amount of vault shares to deposit
     * @param _receiver address to mint extender tokens to
     */
    function deposit(uint256 _shares, address _receiver) external;

    /**
     * @notice Withdraw shares for equal amount of extended share.
     * @param _amount amount of vault extender tokens to burn
     * @param _receiver address to send shares to
     */
    function withdraw(uint256 _amount, address _receiver) external;

    /**
     * @notice Withdraw shares with allowance.
     * @param _from Owner of the shares.
     * @param _to Address receiving the vault shares.
     * @param _amount Amount fo withdraw.
     */
    function withdrawFrom(address _from, address _to, uint256 _amount) external;
}
