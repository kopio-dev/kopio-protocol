// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "kopio/token/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {MockOracle, MockSequencerUptimeFeed} from "mocks/Mocks.sol";
import {ERC20Mock, USDC, USDT, DAI} from "kopio/mocks/ERC20Mock.sol";

import {VaultAsset, VaultConfiguration} from "vault/Types.sol";
import {Vault} from "vault/Vault.sol";
import {TransparentUpgradeableProxy} from "kopio/vendor/TransparentUpgradeableProxy.sol";
import {ONE} from "asset/ONE.sol";
import {IVaultFlashReceiver} from "interfaces/IVaultFlashReceiver.sol";
import {err} from "common/Errors.sol";
import {KopioCLV3} from "periphery/KopioCLV3.sol";

abstract contract VaultTestBase is Test, err {
    Vault public vone;
    ONE public one;

    ERC20Mock public usdc;
    ERC20Mock public dai;
    ERC20Mock public usdt;

    MockOracle public usdcOracle;
    MockOracle public daiOracle;
    MockOracle public usdtOracle;

    address internal user0 = makeAddr("user0");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal user3 = makeAddr("user3");
    address internal user4 = makeAddr("user4");
    address internal feeRecipient = address(0xFEE);

    address internal usdcAddr;
    address internal daiAddr;
    address internal usdtAddr;

    address self = address(this);
    address vaultAddr;
    address oneAddr;

    modifier with(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function setUp() public virtual {
        vm.startPrank(user0);

        vone = Vault(
            address(
                new TransparentUpgradeableProxy(
                    address(new Vault()),
                    address(999),
                    abi.encodeCall(
                        Vault.initialize,
                        (
                            "vONE",
                            "vONE",
                            VaultConfiguration({
                                governance: user0,
                                pendingGovernance: address(0),
                                feeRecipient: feeRecipient,
                                sequencerUptimeFeed: address(new MockSequencerUptimeFeed()),
                                sequencerGracePeriodTime: 3600,
                                oracleDecimals: 8
                            }),
                            address(new KopioCLV3())
                        )
                    )
                )
            )
        );
        one = ONE(address(new TransparentUpgradeableProxy(address(new ONE()), address(999), abi.encodeCall(ONE.initialize, ("ONE", "ONE", user0, address(vone), address(vone))))));

        vm.label(vaultAddr = address(vone), "Vault");
        vm.label(oneAddr = address(one), "ONE");

        vm.warp(3602);

        // tokens
        vm.label(usdcAddr = address(usdc = new USDC()), "USDC");
        vm.label(daiAddr = address(dai = new DAI()), "DAI");
        vm.label(usdtAddr = address(usdt = new USDT()), "USDT");

        // oracles
        usdcOracle = new MockOracle("USDC/USD", 1e8, 8);
        daiOracle = new MockOracle("DAI/USD", 1e8, 8);
        usdtOracle = new MockOracle("USDT/USD", 1e8, 8);

        // add assets
        vone.addAsset(VaultAsset(usdc, usdcOracle, 80000, 0, 0, 0, type(uint248).max, true));
        vone.addAsset(VaultAsset(dai, daiOracle, 80000, 0, 0, 0, type(uint248).max, true));
        vone.addAsset(VaultAsset(usdt, usdtOracle, 80000, 0, 0, 0, type(uint248).max, true));
        vm.stopPrank();

        _approvals();

        usdc.approve(vaultAddr, type(uint256).max);
        usdt.approve(vaultAddr, type(uint256).max);
        dai.approve(vaultAddr, type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Helpers                                  */
    /* -------------------------------------------------------------------------- */

    function _deposit(address user, ERC20Mock asset, uint256 assetsIn) internal with(user) returns (uint256 oneOut) {
        asset.mint(user, assetsIn);
        (oneOut, ) = vone.deposit(address(asset), assetsIn, user);
    }

    function _mint(address user, ERC20Mock asset, uint256 shares) internal with(user) returns (uint256 assetsIn) {
        (uint256 amount, ) = vone.previewMint(address(asset), shares);
        asset.mint(user, amount);
        (assetsIn, ) = vone.mint(address(asset), shares, user);
    }

    function _redeem(address user, ERC20Mock asset, uint256 shares) internal with(user) returns (uint256 assetsOut) {
        (assetsOut, ) = vone.redeem(address(asset), shares, user, user);
    }

    function _maxRedeem(address user, ERC20Mock asset) internal with(user) returns (uint256 assetsOut) {
        (assetsOut, ) = vone.redeem(address(asset), vone.maxRedeem(address(asset), user), user, user);
    }

    function _maxWithdraw(address user, ERC20Mock asset) internal with(user) returns (uint256 sharesIn) {
        (sharesIn, ) = vone.withdraw(address(asset), vone.maxWithdraw(address(asset), user), user, user);
    }

    function _withdraw(address user, ERC20Mock asset, uint256 amount) internal with(user) returns (uint256 oneIn) {
        (oneIn, ) = vone.withdraw(address(asset), amount, user, user);
    }

    function _withdrawFees(ERC20Mock asset) internal {
        vm.prank(user0);
        vone.feeWithdraw(address(asset));
    }

    function _approvals() internal {
        vm.startPrank(user0);
        usdc.approve(address(vone), type(uint256).max);
        dai.approve(address(vone), type(uint256).max);
        usdt.approve(address(vone), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1);
        usdc.approve(address(vone), type(uint256).max);
        dai.approve(address(vone), type(uint256).max);
        usdt.approve(address(vone), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vone), type(uint256).max);
        dai.approve(address(vone), type(uint256).max);
        usdt.approve(address(vone), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user3);
        usdc.approve(address(vone), type(uint256).max);
        dai.approve(address(vone), type(uint256).max);
        usdt.approve(address(vone), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user4);
        usdc.approve(address(vone), type(uint256).max);
        dai.approve(address(vone), type(uint256).max);
        usdt.approve(address(vone), type(uint256).max);
        vm.stopPrank();
    }

    function _logRatios() internal {
        emit log_named_decimal_uint("exchangeRate", vone.exchangeRate(), 18);
        emit log_named_decimal_uint("totalAssets", vone.totalAssets(), 18);
        emit log_named_decimal_uint("totalSupply", vone.totalSupply(), 18);
    }

    function _logBalances(ERC20Mock asset, string memory assetName) internal {
        uint256 balUser0 = asset.balanceOf(user0);
        uint256 decimals = IERC20(address(asset)).decimals();
        emit log_named_decimal_uint(string.concat(assetName, "balanceOf(user0)"), balUser0, decimals);

        uint256 balUser1 = asset.balanceOf(user1);
        emit log_named_decimal_uint(string.concat(assetName, "balanceOf(user1)"), balUser1, decimals);

        uint256 balUser2 = asset.balanceOf(user2);
        emit log_named_decimal_uint(string.concat(assetName, "balanceOf(user2)"), balUser2, decimals);

        uint256 balUser3 = asset.balanceOf(user3);
        emit log_named_decimal_uint(string.concat(assetName, "balanceOf(user3)"), balUser3, decimals);

        uint256 balUser4 = asset.balanceOf(user4);
        emit log_named_decimal_uint(string.concat(assetName, "balanceOf(user4)"), balUser4, decimals);

        uint256 balContract = asset.balanceOf(address(vone));
        emit log_named_decimal_uint(string.concat(assetName, "balanceOf(vault)"), balContract, decimals);
        emit log_named_decimal_uint(string.concat(assetName, "balance combined"), balContract + balUser0 + balUser1 + balUser2 + balUser3 + balUser4, decimals);
        emit log_named_decimal_uint(string.concat(assetName, "totalSupply"), asset.totalSupply(), decimals);

        emit log_named_decimal_uint(string.concat("vault", "balanceOf(user0)"), vone.balanceOf(user0), 18);
        emit log_named_decimal_uint(string.concat("vault", "balanceOf(user1)"), vone.balanceOf(user1), 18);
        emit log_named_decimal_uint(string.concat("vault", "balanceOf(user2)"), vone.balanceOf(user2), 18);
        emit log_named_decimal_uint(string.concat("vault", "balanceOf(user3)"), vone.balanceOf(user3), 18);
        emit log_named_decimal_uint(string.concat("vault", "balanceOf(user4)"), vone.balanceOf(user4), 18);
        emit log_named_decimal_uint(string.concat("vault", "totalSupply"), vone.totalSupply(), 18);
    }

    function _setWithdrawFee(ERC20Mock _asset, uint256 _fee) internal {
        _setFees(_asset, type(uint16).max, uint16(_fee));
    }

    function _setDepositFee(ERC20Mock _asset, uint256 _fee) internal {
        _setFees(_asset, uint16(_fee), type(uint16).max);
    }

    function _setFees(ERC20Mock _asset, uint256 _dfee, uint256 _wfee) internal {
        vm.prank(user0);
        vone.setAssetFees(address(_asset), uint16(_dfee), uint16(_wfee));
    }

    modifier setDeposits(
        ERC20Mock asset,
        uint256 amount,
        bool noFee
    ) {
        uint256 feeBefore = vone.assets(address(asset)).depositFee;

        if (noFee) _setDepositFee(asset, 0);

        _deposit(user4, asset, amount);

        if (noFee) _setDepositFee(asset, feeBefore);
        _;
    }
}

abstract contract VaultFlashTestBase is IVaultFlashReceiver, VaultTestBase {
    function(Flash calldata, bytes calldata) _onVaultFlash;

    function onVaultFlash(Flash calldata params, bytes calldata custom) external {
        if (msg.sender != address(vone)) revert("sender");
        _onVaultFlash(params, custom);
    }

    function _flashApprovals(address _user, uint256 _amount) internal {
        address[] memory assets = new address[](5);
        assets[0] = address(usdc);
        assets[1] = address(dai);
        assets[2] = address(usdt);
        assets[3] = address(one);
        assets[4] = address(vone);

        vm.startPrank(_user);
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).approve(address(one), _amount);
            IERC20(assets[i]).approve(address(vone), _amount);
            IERC20(assets[i]).approve(address(this), _amount);
        }
        vm.stopPrank();
    }

    modifier useCallback(function(Flash calldata, bytes calldata) cb) {
        _onVaultFlash = cb;
        _;
    }

    modifier useDFee(ERC20Mock _asset, uint256 _fee) {
        _setDepositFee(_asset, uint16(_fee));
        _;
    }

    modifier useWFee(ERC20Mock _asset, uint256 _fee) {
        _setWithdrawFee(_asset, uint16(_fee));
        _;
    }

    modifier useFees(
        ERC20Mock asset,
        uint256 _dfee,
        uint256 _wfee
    ) {
        _setFees(asset, _dfee, _wfee);
        _;
    }

    function mint(address token, uint256 _amount, address _to) internal {
        ERC20Mock(token).mint(_to, _amount);
    }

    function vaultDeposit(address token, uint256 _amount, address _to) internal {
        ERC20Mock(token).mint(address(this), _amount);
        vone.deposit(address(token), _amount, _to);
    }

    function vaultMint(address token, uint256 _amount, address _to) internal {
        (uint256 assets, ) = vone.previewMint(address(token), _amount);
        ERC20Mock(token).mint(address(this), assets);
        vone.mint(address(token), _amount, _to);
    }

    modifier ensureRate() {
        uint256 rate = vone.exchangeRate();
        assertEq(rate, vone.baseRate(), "rate-before");
        _;
        assertEq(vone.exchangeRate(), rate, "rate-after");
    }
}
