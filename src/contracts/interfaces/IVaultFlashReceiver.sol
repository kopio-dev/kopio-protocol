// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVaultFlash {
    enum FlashKind {
        Shares,
        Assets
    }

    struct Flash {
        address asset;
        uint256 assets;
        uint256 shares;
        address receiver;
        FlashKind kind;
    }

    struct FlashData {
        uint256 balIn;
        uint256 tSupplyIn;
        uint256 tAssetsIn;
        uint256 depositsIn;
    }

    error FLASH_KIND_NOT_SUPPORTED(FlashKind);
}

interface IVaultFlashReceiver is IVaultFlash {
    function onVaultFlash(Flash calldata, bytes calldata) external;
}
