// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {IVaultFlash} from "interfaces/IVaultFlashReceiver.sol";

interface VEvent {
    /**
     * @notice Emitted when a deposit/mint is made
     * @param caller Caller of the deposit/mint
     * @param receiver Receiver of the minted assets
     * @param asset Asset that was deposited/minted
     * @param assetsIn Amount of assets deposited
     * @param sharesOut Amount of shares minted
     */
    event Deposit(address indexed caller, address indexed receiver, address indexed asset, uint256 assetsIn, uint256 sharesOut);

    /**
     * @notice Emitted when a new oracle is set for an asset
     * @param asset Asset that was updated
     * @param feed Feed that was set
     * @param st Time in seconds for the feed to be considered stale
     */
    event OracleSet(address indexed asset, address indexed feed, uint256 st);

    /**
     * @notice Emitted when a new asset is added to the shares contract
     * @param asset Address of the asset
     * @param feed Price feed of the asset
     * @param st Time in seconds for the feed to be considered stale
     * @param depositLimit Deposit limit of the asset
     */
    event AssetAdded(address indexed asset, address indexed feed, uint256 st, uint256 depositLimit);

    /**
     * @notice Emitted when a previously existing asset is removed from the shares contract
     * @param asset Asset that was removed
     */
    event AssetRemoved(address indexed asset);

    /**
     * @notice Emitted when a withdraw/redeem is made
     * @param caller Caller of the withdraw/redeem
     * @param receiver Receiver of the withdrawn assets
     * @param asset Asset that was withdrawn/redeemed
     * @param owner Owner of the withdrawn assets
     * @param assetsOut Amount of assets withdrawn
     * @param sharesIn Amount of shares redeemed
     */
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed asset,
        address owner,
        uint256 assetsOut,
        uint256 sharesIn
    );
    event VaultFlash(
        address indexed caller,
        address indexed ownerOrReceiver,
        address indexed asset,
        uint256 assets,
        uint256 shares,
        IVaultFlash.FlashKind kind
    );
}
