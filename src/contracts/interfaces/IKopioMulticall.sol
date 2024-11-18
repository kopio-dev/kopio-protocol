// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface Multi {
    /**
     * @notice The action for an operation.
     */
    enum Action {
        ICDPDeposit,
        ICDPWithdraw,
        ICDPRepay,
        ICDPBorrow,
        SCDPDeposit,
        SCDPTrade,
        SCDPWithdraw,
        SCDPClaim,
        Unwrap,
        Wrap,
        VaultDeposit,
        VaultRedeem,
        AMMExactInput,
        WrapNative,
        UnwrapNative
    }

    /**
     * @notice An operation to execute.
     * @param action The operation to execute.
     * @param data The data for the operation.
     */
    struct Op {
        Action action;
        Data data;
    }

    /**
     * @notice Data for an operation.
     * @param tokenIn The tokenIn to use, or address(0) if none.
     * @param amountIn The amount of tokenIn to use, or 0 if none.
     * @param modeIn The mode for tokensIn.
     * @param tokenOut The tokenOut to use, or address(0) if none.
     * @param amountOut The amount of tokenOut to use, or 0 if none.
     * @param modeOut The mode for tokensOut.
     * @param minOut The minimum amount of tokenOut to receive, or 0 if none.
     * @param path The path for the Uniswap V3 swap, or empty if none.
     */
    struct Data {
        address tokenIn;
        uint96 amountIn;
        ModeIn modeIn;
        address tokenOut;
        uint96 amountOut;
        ModeOut modeOut;
        uint128 minOut;
        bytes path;
    }

    /**
     * @notice The token in mode for an operation.
     * @param None Operation requires no tokens in.
     * @param Pull Operation pulls tokens in from sender.
     * @param Balance Operation uses the existing contract balance for tokens in.
     * @param UseOpIn Operation uses the existing contract balance for tokens in, but only the amountIn specified.
     */
    enum ModeIn {
        None,
        Native,
        Pull,
        Balance,
        UseOpIn,
        BalanceUnwrapNative,
        BalanceWrapNative,
        BalanceNative
    }

    /**
     * @notice The token out mode for an operation.
     * @param None Operation requires no tokens out.
     * @param ReturnToSenderNative Operation will unwrap and transfer native to sender.
     * @param ReturnToSender Operation returns tokens received to sender.
     * @param LeaveInContract Operation leaves tokens received in the contract for later use.
     */
    enum ModeOut {
        None,
        ReturnNative,
        Return,
        Leave
    }

    /**
     * @notice The result of an operation.
     * @param tokenIn The tokenIn to use.
     * @param amountIn The amount of tokenIn used.
     * @param tokenOut The tokenOut to receive from the operation.
     * @param amountOut The amount of tokenOut received.
     */
    struct Result {
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 amountOut;
    }

    error NO_MULTI_ALLOWANCE(Action action, address token, string symbol);
    error ZERO_AMOUNT_IN(Action action, address token, string symbol);
    error ZERO_NATIVE_IN(Action action);
    error VALUE_NOT_ZERO(Action action, uint256 value);
    error INVALID_NATIVE_TOKEN_IN(Action action, address token, string symbol);
    error ZERO_OR_INVALID_AMOUNT_IN(Action action, address token, string symbol, uint256 balance, uint256 amountOut);
    error INVALID_ACTION(Action action);

    error NATIVE_SYNTH_WRAP_NOT_ALLOWED(Action action, address token, string symbol);

    error TOKENS_IN_MODE_WAS_NONE_BUT_ADDRESS_NOT_ZERO(Action action, address token);
    error TOKENS_OUT_MODE_WAS_NONE_BUT_ADDRESS_NOT_ZERO(Action action, address token);

    error INSUFFICIENT_UPDATE_FEE(uint256 updateFee, uint256 amountIn);

    error LENGTH_MISMATCH(uint256 a, uint256 b);

    enum CallMode {
        None,
        Call,
        Delegate,
        Static
    }

    struct Target {
        uint248 sender;
        CallMode mode;
    }

    struct Call {
        CallMode mode;
        uint256 value;
        address target;
        bytes data;
    }

    error INVALID_RAW_CALL(Call);
}

interface IKopioMulticall is Multi {
    event MulticallExecuted(address _sender, Op[] ops, Result[] results);
    function execute(Op[] calldata ops, bytes[] calldata prices) external payable returns (Result[] memory);
    function executeRaw(bytes[] calldata) external payable returns (bytes[] memory);
    function setTargets(address[] calldata, bytes4[] calldata, Target[] calldata) external;
    function getRawCall(bytes calldata data) external view returns (Call memory);
}
