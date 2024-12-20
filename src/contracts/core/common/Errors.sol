// SPDX-License-Identifier: BUSL-1.1
pragma solidity <0.9.0;
import {OraclePrice} from "./Types.sol";

// solhint-disable

function id(address t) view returns (err.ID memory r) {
    r.addr = t;
    if (t.code.length != 0) r.symbol = tkn(t).symbol();
}

interface tkn {
    function symbol() external view returns (string memory);
}

interface err {
    struct ID {
        string symbol;
        address addr;
    }
    error INSUFFICIENT_ASSETS(address asset, uint256 amount, uint256 max);
    error NOT_INITIALIZING();
    error TO_WAD_AMOUNT_IS_NEGATIVE(int256);
    error STRING_HEX_LENGTH_INSUFFICIENT();
    error SAFETY_COUNCIL_NOT_ALLOWED();
    error SAFETY_COUNCIL_ALREADY_EXISTS(address given, address existing);
    error MULTISIG_NOT_ENOUGH_OWNERS(address, uint256 owners, uint256 required);
    error ACCESS_CONTROL_NOT_SELF(address who, address self);
    error MARKET_CLOSED(ID, string);
    error SCDP_ASSET_ECONOMY(ID, uint256 seizeReductionPct, ID, uint256 repayIncreasePct);
    error ICDP_ASSET_ECONOMY(ID, uint256 seizeReductionPct, ID, uint256 repayIncreasePct);
    error INVALID_TICKER(ID, string ticker);
    error ASSET_SET_FEEDS_FAILED(ID);
    error ASSET_PAUSED_FOR_THIS_ACTION(ID, uint8 action);
    error NOT_COVER_ASSET(ID);
    error NOT_ENABLED(ID);
    error NOT_CUMULATED(ID);
    error NOT_DEPOSITABLE(ID);
    error NOT_MINTABLE(ID);
    error NOT_SWAPPABLE(ID);
    error NOT_COLLATERAL(ID);
    error INVALID_ASSET(address);
    error NO_GLOBAL_DEPOSITS(ID);
    error ASSET_CANNOT_BE_FEE_ASSET(ID);
    error ASSET_NOT_VALID_DEPOSIT_ASSET(ID);
    error ASSET_ALREADY_ENABLED(ID);
    error ASSET_ALREADY_DISABLED(ID);
    error NOT_INCOME_ASSET(address);
    error ASSET_EXISTS(ID);
    error VOID_ASSET();
    error CANNOT_REMOVE_COLLATERAL_THAT_HAS_USER_DEPOSITS(ID);
    error CANNOT_REMOVE_SWAPPABLE_ASSET_THAT_HAS_DEBT(ID);
    error INVALID_KOPIO(ID kopio);
    error INVALID_SHARE(ID share, ID kopio);
    error IDENTICAL_ASSETS(ID);
    error WITHDRAW_NOT_SUPPORTED();
    error MINT_NOT_SUPPORTED();
    error DEPOSIT_NOT_SUPPORTED();
    error REDEEM_NOT_SUPPORTED();
    error NATIVE_TOKEN_DISABLED(ID);
    error EXCEEDS_ASSET_DEPOSIT_LIMIT(ID, uint256 deposits, uint256 limit);
    error EXCEEDS_ASSET_MINTING_LIMIT(ID, uint256 deposits, uint256 limit);
    error UINT128_OVERFLOW(ID, uint256 deposits, uint256 limit);
    error INVALID_SENDER(address, address);
    error INVALID_MIN_DEBT(uint256 invalid, uint256 valid);
    error INVALID_SCDP_FEE(ID, uint256 invalid, uint256 valid);
    error INVALID_MCR(uint256 invalid, uint256 valid);
    error MLR_LESS_THAN_LT(uint256 mlt, uint256 lt);
    error INVALID_LIQ_THRESHOLD(uint256 lt, uint256 min, uint256 max);
    error INVALID_PROTOCOL_FEE(ID, uint256 invalid, uint256 valid);
    error INVALID_ASSET_FEE(ID, uint256 invalid, uint256 valid);
    error INVALID_ORACLE_DEVIATION(uint256 invalid, uint256 valid);
    error INVALID_ORACLE_TYPE(uint8 invalid);
    error INVALID_FEE_RECIPIENT(address invalid);
    error INVALID_LIQ_INCENTIVE(ID, uint256 invalid, uint256 min, uint256 max);
    error INVALID_DFACTOR(ID, uint256 invalid, uint256 valid);
    error INVALID_CFACTOR(ID, uint256 invalid, uint256 valid);
    error INVALID_ICDP_FEE(ID, uint256 invalid, uint256 valid);
    error INVALID_PRICE_PRECISION(uint256 decimals, uint256 valid);
    error INVALID_COVER_THRESHOLD(uint256 threshold, uint256 max);
    error INVALID_COVER_INCENTIVE(uint256 incentive, uint256 min, uint256 max);
    error INVALID_DECIMALS(ID, uint256 decimals);
    error INVALID_FEE(ID, uint256 invalid, uint256 valid);
    error INVALID_FEE_TYPE(uint8 invalid, uint8 valid);
    error INVALID_KOPIO_OPERATOR(ID, address invalid, address valid);
    error INVALID_DENOMINATOR(ID, uint256 denominator, uint256 valid);
    error INVALID_OPERATOR(ID, address who, address valid);
    error INVALID_SUPPLY_LIMIT(ID, uint256 invalid, uint256 valid);
    error NEGATIVE_PRICE(address asset, int256 price);
    error INVALID_PYTH_PRICE(bytes32 id, uint256 price);
    error STALE_PRICE(string ticker, uint256 price, uint256 age, uint256 st);
    error STALE_PUSH_PRICE(ID asset, string ticker, int256 price, uint8 oracleType, address feed, uint256 age, uint256 st);
    error PRICE_UNSTABLE(uint256 primaryPrice, uint256 referencePrice, uint256 deviationPct);
    error ZERO_OR_STALE_VAULT_PRICE(ID, address, uint256);
    error ZERO_OR_STALE_PRICE(string ticker, uint8[2] oracles);
    error STALE_ORACLE(uint8 oracleType, address feed, uint256 time, uint256 st);
    error INVALID_ORACLE_PRICE(OraclePrice);
    error NO_ORACLE_SET(string ticker);
    error NOT_SUPPORTED_YET();
    error WRAP_NOT_SUPPORTED();
    error BURN_AMOUNT_OVERFLOW(ID, uint256 burnAmount, uint256 debtAmount);
    error PAUSED(address who);
    error L2_SEQUENCER_DOWN();
    error FEED_ZERO_ADDRESS(string ticker);
    error CANNOT_RE_ENTER();
    error PYTH_ID_ZERO(string ticker);
    error ARRAY_LENGTH_MISMATCH(string ticker, uint256 arr1, uint256 arr2);
    error COLLATERAL_VALUE_GREATER_THAN_REQUIRED(uint256 collateralValue, uint256 minCollateralValue, uint32 ratio);
    error COLLATERAL_VALUE_GREATER_THAN_COVER_THRESHOLD(uint256 collateralValue, uint256 minCollateralValue, uint48 ratio);
    error ACCOUNT_COLLATERAL_TOO_LOW(address who, uint256 collateralValue, uint256 minCollateralValue, uint32 ratio);
    error COLLATERAL_TOO_LOW(uint256 collateralValue, uint256 minCollateralValue, uint32 ratio);
    error NOT_LIQUIDATABLE(address who, uint256 collateralValue, uint256 minCollateralValue, uint32 ratio);
    error CANNOT_LIQUIDATE_SELF();
    error LIQUIDATION_AMOUNT_GREATER_THAN_DEBT(ID repayAsset, uint256 repayAmount, uint256 availableAmount);
    error LIQUIDATION_SEIZED_LESS_THAN_EXPECTED(ID, uint256, uint256);
    error ZERO_VALUE_LIQUIDATION(ID repayAsset, ID seizeAsset);
    error NO_DEPOSITS(address who, ID);
    error NOT_ENOUGH_DEPOSITS(address who, ID, uint256 requested, uint256 deposits);
    error NOT_MINTED(address account, ID, address[] accountCollaterals);
    error NOT_DEPOSITED(address account, ID, address[] accountCollaterals);
    error ARRAY_INDEX_OUT_OF_BOUNDS(ID element, uint256 index, address[] elements);
    error ELEMENT_DOES_NOT_MATCH_PROVIDED_INDEX(ID element, uint256 index, address[] elements);
    error NO_FEES_TO_CLAIM(ID asset, address claimer);
    error REPAY_OVERFLOW(ID repayAsset, ID seizeAsset, uint256 invalid, uint256 valid);
    error INCOME_AMOUNT_IS_ZERO(ID incomeAsset);
    error NO_LIQUIDITY_TO_GIVE_INCOME_FOR(ID incomeAsset, uint256 userDeposits, uint256 totalDeposits);
    error NOT_ENOUGH_SWAP_DEPOSITS_TO_SEIZE(ID repayAsset, ID seizeAsset, uint256 invalid, uint256 valid);
    error SWAP_ROUTE_NOT_ENABLED(ID assetIn, ID assetOut);
    error RECEIVED_LESS_THAN_DESIRED(ID, uint256 invalid, uint256 valid);
    error SWAP_ZERO_AMOUNT_IN(ID tokenIn);
    error MAX_DEPOSIT_EXCEEDED(ID asset, uint256 assetsIn, uint256 maxDeposit);
    error COLLATERAL_AMOUNT_LOW(ID kopioCollateral, uint256 amount, uint256 minAmount);
    error MINT_VALUE_LESS_THAN_MIN_DEBT_VALUE(ID, uint256 value, uint256 minRequiredValue);
    error NOT_A_CONTRACT(address who);
    error NO_ALLOWANCE(address spender, address owner, uint256 requested, uint256 allowed);
    error NOT_ENOUGH_BALANCE(address who, uint256 requested, uint256 available);
    error SENDER_NOT_OPERATOR(ID, address sender, address operator);
    error ZERO_SHARES_FROM_ASSETS(ID, uint256 assets, ID);
    error ZERO_SHARES_IN(address asset, uint256 assets);
    error ZERO_ASSETS_FROM_SHARES(ID, uint256 shares, ID);
    error ZERO_ASSETS_OUT(address);
    error ZERO_ASSETS_IN(address);
    error ZERO_ADDRESS();
    error ZERO_DEPOSIT(ID);
    error ZERO_AMOUNT(ID);
    error ZERO_WITHDRAW(ID);
    error ZERO_MINT(ID);
    error SDI_DEBT_REPAY_OVERFLOW(uint256 debt, uint256 repay);
    error ZERO_REPAY(ID, uint256 repayAmount, uint256 seizeAmount);
    error ZERO_BURN(ID);
    error ZERO_DEBT(ID);
    error BatchResult(uint256 timestamp, bytes[] results);
    /**
     * @notice Cannot directly rethrow or redeclare panic errors in try/catch - so using a similar error instead.
     * @param code The panic code received.
     */
    error Panicked(uint256 code);
}
