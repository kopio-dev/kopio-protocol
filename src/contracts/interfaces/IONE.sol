// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IKopioIssuer} from "interfaces/IKopioIssuer.sol";
import {IVaultExtender} from "interfaces/IVaultExtender.sol";
import {IERC20Permit} from "kopio/token/IERC20Permit.sol";
import {IVault} from "interfaces/IVault.sol";
import {IERC165} from "vendor/IERC165.sol";

interface IONE is IERC20Permit, IVaultExtender, IKopioIssuer, IERC165 {
    function protocol() external view returns (address);
    /**
     * @notice This function adds ONE to circulation
     * Caller must be a contract and have the OPERATOR_ROLE
     * @param amount amount to mint
     * @param to address to mint tokens to
     * @return uint256 amount minted
     */
    function issue(uint256 amount, address to) external returns (uint256);

    /**
     * @notice This function removes ONE from circulation
     * Caller must be a contract and have the OPERATOR_ROLE
     * @param amount amount to burn
     * @param from address to burn tokens from
     * @return uint256 amount burned
     */
    function destroy(uint256 amount, address from) external returns (uint256);

    function vault() external view returns (IVault);
    /**
     * @notice Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function pause() external;

    /**
     * @notice  Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function unpause() external;

    /**
     * @notice Exchange rate of vONE to USD.
     * @return rate vONE/USD exchange rate.
     */
    function exchangeRate() external view returns (uint256 rate);
}
