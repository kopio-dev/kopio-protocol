// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IAggregatorV3} from "kopio/vendor/IAggregatorV3.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";
import {IVault} from "interfaces/IVault.sol";
import {IVaultFlashReceiver} from "interfaces/IVaultFlashReceiver.sol";

import {Arrays} from "libs/Arrays.sol";
import {FixedPointMath} from "vendor/FixedPointMath.sol";

import {err} from "common/Errors.sol";

import {VaultAsset, VaultConfiguration} from "vault/Types.sol";
import {ERC20Upgradeable} from "kopio/token/ERC20Upgradeable.sol";
import {IKopioCLV3} from "kopio/IKopioCLV3.sol";
import {isSequencerUp} from "common/funcs/Utils.sol";
import {Percents} from "common/Constants.sol";
import {Utils} from "kopio/utils/Libs.sol";

using SafeTransfer for IERC20;
using Arrays for address[];
using Utils for uint256;
using FixedPointMath for uint256;

abstract contract VaultBase is ERC20Upgradeable, IVault, err {
    VaultConfiguration internal _config;
    mapping(address => VaultAsset) internal _assets;
    address[] public assetList;
    uint256 public baseRate;
    mapping(address => uint256) internal _deposits;
    IKopioCLV3 public kopioCLV3;

    constructor() {
        _disableInitializers();
    }

    modifier onlyGovernance() {
        if (msg.sender != _config.governance) revert INVALID_SENDER(msg.sender, _config.governance);
        _;
    }

    function _pullAssets(IERC20 asset, address from, uint256 amount) internal returns (uint256) {
        uint256 balance = asset.balanceOf(address(this));

        asset.safeTransferFrom(from, address(this), amount);

        amount = asset.balanceOf(address(this)) - balance;

        if (amount != 0) return amount;

        revert ZERO_ASSETS_IN(address(asset));
    }

    function _sendAssets(IERC20 asset, address receiver, uint256 amount) internal returns (uint256) {
        uint256 balance = asset.balanceOf(address(this));

        asset.safeTransfer(receiver, amount);

        amount = balance - asset.balanceOf(address(this));

        if (amount != 0) return amount;

        revert ZERO_ASSETS_OUT(address(asset));
    }

    function _spendAllowance(address owner, uint256 amount) internal {
        if (msg.sender == owner) return;

        uint256 allowed = _allowances[owner][msg.sender];
        if (allowed < amount) revert NO_ALLOWANCE(msg.sender, owner, amount, allowed);

        unchecked {
            if (allowed != type(uint256).max) _allowances[owner][msg.sender] = allowed - amount;
        }
    }

    /// @notice Gets the price of an asset from the oracle speficied.
    function _price(VaultAsset storage asset) internal view returns (uint256) {
        if (!isSequencerUp(_config.sequencerUptimeFeed, _config.sequencerGracePeriodTime)) {
            revert err.L2_SEQUENCER_DOWN();
        }
        IKopioCLV3.Answer memory data = kopioCLV3.getAnswer(address(asset.feed));
        if (data.age > asset.staleTime) revert err.STALE_PRICE(asset.token.symbol(), data.answer, data.age, asset.staleTime);
        return data.answer;
    }

    /// @notice Equivalent USD value in wad precision for @param amount of @param asset.
    function _usdWad(VaultAsset storage asset, uint256 amount) internal view returns (uint256) {
        return (amount * _price(asset)).toDec(asset.decimals + _config.oracleDecimals, 18);
    }

    /// @notice Equivalent @return uint256 amount of @param asset for the @param valueWad.
    function _toAmount(VaultAsset storage asset, uint256 valueWad) internal view returns (uint256) {
        uint256 valueScaled = (valueWad * 1e18) / 10 ** ((36 - _config.oracleDecimals) - asset.decimals);
        return valueScaled / _price(asset);
    }

    function _unitOf(VaultAsset storage asset) internal view returns (uint256) {
        return (10 ** (18 - asset.decimals));
    }

    function _addrOr(address a, address b) internal pure returns (address) {
        return a == address(0) ? b : a;
    }

    function previewDeposit(address, uint256) public view virtual returns (uint256, uint256);
    function previewWithdraw(address, uint256) public view virtual returns (uint256, uint256);
    function previewMint(address, uint256) public view virtual returns (uint256, uint256);
    function previewRedeem(address, uint256) public view virtual returns (uint256, uint256);

    function maxDeposit(address) public view virtual returns (uint256);
    function maxMint(address) public view virtual returns (uint256);
    function maxRedeem(address) public view virtual returns (uint256);
    function maxWithdraw(address) public view virtual returns (uint256);

    function totalAssets() public view virtual returns (uint256);
    function exchangeRate() external view virtual returns (uint256);

    function deposit(address, uint256, address) public virtual override returns (uint256, uint256);
    function mint(address, uint256, address) public virtual override returns (uint256, uint256);
    function redeem(address, uint256, address, address) public virtual override returns (uint256, uint256);
    function withdraw(address, uint256, address, address) public virtual override returns (uint256, uint256);

    function flash(address, uint256, address, bytes calldata) external virtual override returns (uint256, uint256);
    function flash(address, uint256, address, address, bytes calldata) external virtual override returns (uint256, uint256);
}

/**
 * @title Vault - multi-token vault (ERC4626 derived)
 * @author the kopio project
 * @notice Users deposit tokens into the vault and receive shares of equal value in return.
 * @notice Shares are redeemable for the underlying tokens at any time.
 * @notice Exchange rate of SHARE/USD is determined by the total value of the underlying tokens in the vault and the share supply.
 */
abstract contract VaultLogic is VaultBase {
    /// @inheritdoc IVault
    function totalAssets() public view virtual override returns (uint256 result) {
        address asset;
        for (uint256 i; i < assetList.length; ) {
            unchecked {
                uint256 deposits = _deposits[asset = assetList[i]];
                if (deposits != 0) result += _usdWad(_assets[asset], deposits);
                ++i;
            }
        }
    }

    /// @inheritdoc IVault
    function exchangeRate() external view virtual override returns (uint256) {
        (uint256 tSupply, uint256 tAssets) = _state();
        return tSupply.divWadUp(tAssets);
    }

    function _state() internal view returns (uint256 tSupply, uint256 tAssets) {
        if ((tSupply = totalSupply()) == 0 || (tAssets = totalAssets()) == 0) {
            return (1 ether, baseRate);
        }
    }

    /// @notice Validate and store inflows
    function _handleIn(
        address assetAddr,
        uint256 assetsIn,
        uint256 assetFee,
        uint256 sharesOut,
        address receiver
    ) internal returns (uint256 newDeposits) {
        VaultAsset storage asset = _assets[assetAddr];
        if (!asset.enabled) revert INVALID_ASSET(assetAddr);

        newDeposits = (_deposits[assetAddr] += assetsIn - assetFee);
        if (newDeposits > asset.maxDeposits) revert INSUFFICIENT_ASSETS(assetAddr, _deposits[assetAddr], asset.maxDeposits);

        _mint(_addrOr(receiver, msg.sender), sharesOut);
    }

    /// @notice Validate and store outflows
    function _handleOut(address assetAddr, uint256 assetsOut, uint256 assetFee, uint256 sharesIn, address owner) internal {
        if (!_assets[assetAddr].enabled) revert INVALID_ASSET(assetAddr);

        if (sharesIn == 0) revert ZERO_SHARES_IN(assetAddr, assetsOut);

        uint256 maxOut = maxWithdraw(assetAddr);
        if (assetsOut > maxOut) revert NOT_ENOUGH_BALANCE(address(this), assetsOut, maxOut);
        if (_balances[owner] < sharesIn) revert NOT_ENOUGH_BALANCE(owner, _balances[owner], sharesIn);

        _deposits[assetAddr] -= assetsOut + assetFee;
        _spendAllowance(owner, sharesIn);
        _burn(owner, sharesIn);
    }

    function _previewDeposit(
        VaultAsset storage asset,
        uint256 assetsIn
    ) internal view returns (uint256 sharesOut, uint256 assetFee) {
        (uint256 tSupply, uint256 tAssets) = _state();
        (assetsIn, assetFee) = _feeDown(assetsIn, asset.depositFee);
        sharesOut = _usdWad(asset, assetsIn).mulDivDown(tSupply, tAssets);
    }

    function _previewWithdraw(
        VaultAsset storage asset,
        uint256 assetsOut
    ) internal view returns (uint256 sharesIn, uint256 assetFee) {
        (uint256 tSupply, uint256 tAssets) = _state();
        (assetsOut, assetFee) = _feeUp(assetsOut, asset.withdrawFee);
        sharesIn = _usdWad(asset, assetsOut).mulDivUp(tSupply, tAssets);
    }

    function _previewMint(
        VaultAsset storage asset,
        uint256 sharesOut
    ) internal view returns (uint256 assetsIn, uint256 assetFee) {
        (uint256 tSupply, uint256 tAssets) = _state();
        return _feeUp(_toAmount(asset, sharesOut.mulDivUp(tAssets, tSupply)), asset.depositFee);
    }

    function _previewRedeem(
        VaultAsset storage asset,
        uint256 sharesIn
    ) internal view returns (uint256 assetsOut, uint256 assetFee) {
        (uint256 tSupply, uint256 tAssets) = _state();
        return _feeDown(_toAmount(asset, sharesIn.mulDivDown(tAssets, tSupply)), asset.withdrawFee);
    }

    /// @inheritdoc IVault
    function maxDeposit(address asset) public view virtual override returns (uint256 max) {
        max = _assets[asset].maxDeposits - _deposits[asset];
    }

    /// @inheritdoc IVault
    function maxMint(address asset) public view virtual override returns (uint256 max) {
        (max, ) = previewDeposit(asset, maxDeposit(asset));
    }

    /// @inheritdoc IVault
    function maxRedeem(address asset) public view virtual override returns (uint256 max) {
        (max, ) = previewWithdraw(asset, maxWithdraw(asset));
    }

    /// @inheritdoc IVault
    function maxWithdraw(address asset) public view virtual override returns (uint256 max) {
        (max, ) = _feeDown(_deposits[asset], _assets[asset].withdrawFee);
    }

    /// @notice Calculates the `fees` and `amountOut` required for `amount` after fees.
    function _feeUp(uint256 amount, uint256 fee) internal pure returns (uint256 amountOut, uint256 fees) {
        amountOut = amount;

        if (fee != 0) {
            amountOut = amount.pdiv(Percents.HUNDRED - fee);
            fees = amountOut - amount;
        }
    }

    /// @notice Calculates `amountOut` from `amount` after `fees`.
    function _feeDown(uint256 amount, uint256 fee) internal pure returns (uint256 amountOut, uint256 fees) {
        amountOut = amount;

        if (fee != 0) {
            fees = amount.pmul(fee);
            amountOut -= fees;
        }
    }
}

abstract contract VaultCore is VaultLogic {
    /// @inheritdoc IVault
    function deposit(
        address assetAddr,
        uint256 assetsIn,
        address receiver
    ) public virtual override returns (uint256 sharesOut, uint256 assetFee) {
        (sharesOut, assetFee) = _previewDeposit(_assets[assetAddr], assetsIn);

        assetsIn = _pullAssets(IERC20(assetAddr), msg.sender, assetsIn);

        _handleIn(assetAddr, assetsIn, assetFee, sharesOut, receiver);

        emit Deposit(msg.sender, receiver, assetAddr, assetsIn, sharesOut);
    }

    /// @inheritdoc IVault
    function mint(
        address assetAddr,
        uint256 sharesOut,
        address receiver
    ) public virtual override returns (uint256 assetsIn, uint256 assetFee) {
        (assetsIn, assetFee) = _previewMint(_assets[assetAddr], sharesOut);

        assetsIn = _pullAssets(IERC20(assetAddr), msg.sender, assetsIn);

        _handleIn(assetAddr, assetsIn, assetFee, sharesOut, receiver);

        emit Deposit(msg.sender, receiver, assetAddr, assetsIn, sharesOut);
    }

    /// @inheritdoc IVault
    function redeem(
        address assetAddr,
        uint256 sharesIn,
        address receiver,
        address owner
    ) public virtual override returns (uint256 assetsOut, uint256 assetFee) {
        (assetsOut, assetFee) = _previewRedeem(_assets[assetAddr], sharesIn);

        assetsOut = _sendAssets(IERC20(assetAddr), receiver = _addrOr(receiver, owner), assetsOut);

        _handleOut(assetAddr, assetsOut, assetFee, sharesIn, owner);

        emit Withdraw(msg.sender, receiver, assetAddr, owner, assetsOut, sharesIn);
    }

    /// @inheritdoc IVault
    function withdraw(
        address assetAddr,
        uint256 assetsOut,
        address receiver,
        address owner
    ) public virtual override returns (uint256 sharesIn, uint256 assetFee) {
        (sharesIn, assetFee) = _previewWithdraw(_assets[assetAddr], assetsOut);

        assetsOut = _sendAssets(IERC20(assetAddr), receiver = _addrOr(receiver, owner), assetsOut);

        _handleOut(assetAddr, assetsOut, assetFee, sharesIn, owner);

        emit Withdraw(msg.sender, receiver, assetAddr, owner, assetsOut, sharesIn);
    }

    /// @inheritdoc IVault
    function flash(
        address assetAddr,
        uint256 sharesOut,
        address receiver,
        bytes calldata data
    ) external override returns (uint256 assetsIn, uint256 assetFee) {
        VaultAsset storage asset = _assets[assetAddr];
        (assetsIn, assetFee) = _previewMint(asset, sharesOut);
        require(sharesOut > _unitOf(asset) * 100, INSUFFICIENT_ASSETS(assetAddr, sharesOut, 0));

        FlashData memory info;
        info.tSupplyIn = _totalSupply;
        info.depositsIn = _handleIn(assetAddr, assetsIn, assetFee, sharesOut, receiver = _addrOr(receiver, msg.sender));

        info.tAssetsIn = totalAssets();
        info.balIn = IERC20(assetAddr).balanceOf(address(this));

        IVaultFlashReceiver(msg.sender).onVaultFlash(Flash(assetAddr, assetsIn, sharesOut, receiver, FlashKind.Shares), data);

        info.depositsIn = _deposits[assetAddr] - info.depositsIn;
        info.balIn = (IERC20(assetAddr).balanceOf(address(this)) - info.balIn).pmul(100e2 - asset.depositFee) - info.depositsIn;

        uint256 tAssets = totalAssets();

        info.tSupplyIn = (_totalSupply - info.tSupplyIn).mulDivUp(tAssets, _totalSupply);
        info.tAssetsIn = (tAssets - info.tAssetsIn) + _usdWad(asset, info.balIn);

        if (info.tAssetsIn < info.tSupplyIn && info.tSupplyIn - info.tAssetsIn > _unitOf(asset)) {
            revert INSUFFICIENT_ASSETS(assetAddr, info.tAssetsIn + assetFee, info.tSupplyIn + assetFee);
        }

        emit VaultFlash(msg.sender, receiver, assetAddr, assetsIn, sharesOut, FlashKind.Shares);
    }

    /// @inheritdoc IVault
    function flash(
        address assetAddr,
        uint256 assetsOut,
        address receiver,
        address owner,
        bytes calldata data
    ) external override returns (uint256 sharesIn, uint256 assetFee) {
        (sharesIn, assetFee) = _previewWithdraw(_assets[assetAddr], assetsOut);
        assetsOut = _sendAssets(IERC20(assetAddr), (receiver = _addrOr(receiver, msg.sender)), assetsOut);

        IVaultFlashReceiver(msg.sender).onVaultFlash(Flash(assetAddr, assetsOut, sharesIn, receiver, FlashKind.Assets), data);

        _handleOut(assetAddr, assetsOut, assetFee, sharesIn, owner);

        emit VaultFlash(msg.sender, owner, assetAddr, assetsOut, sharesIn, FlashKind.Assets);
    }

    /// @inheritdoc IVault
    function previewDeposit(
        address assetAddr,
        uint256 assetsIn
    ) public view virtual override returns (uint256 sharesOut, uint256 assetFee) {
        return _previewDeposit(_assets[assetAddr], assetsIn);
    }

    /// @inheritdoc IVault
    function previewMint(
        address assetAddr,
        uint256 sharesOut
    ) public view virtual override returns (uint256 assetsIn, uint256 assetFee) {
        return _previewMint(_assets[assetAddr], sharesOut);
    }

    /// @inheritdoc IVault
    function previewWithdraw(
        address assetAddr,
        uint256 assetsOut
    ) public view virtual override returns (uint256 sharesIn, uint256 assetFee) {
        return _previewWithdraw(_assets[assetAddr], assetsOut);
    }

    /// @inheritdoc IVault
    function previewRedeem(
        address assetAddr,
        uint256 sharesIn
    ) public view virtual override returns (uint256 assetsOut, uint256 assetFee) {
        return _previewRedeem(_assets[assetAddr], sharesIn);
    }

    function maxDeposit(address assetAddr, address user) public view returns (uint256 max) {
        uint256 maxIn = maxDeposit(assetAddr);
        uint256 balance = IERC20(assetAddr).balanceOf(user);
        return balance < maxIn ? balance : maxIn;
    }

    function maxMint(address assetAddr, address user) public view returns (uint256 max) {
        (max, ) = previewDeposit(assetAddr, maxDeposit(assetAddr, user));
    }

    function maxWithdraw(address assetAddr, address user) public view returns (uint256 max) {
        (max, ) = previewRedeem(assetAddr, maxRedeem(assetAddr, user));
    }

    function maxRedeem(address assetAddr, address user) public view returns (uint256 max) {
        uint256 maxIn = maxRedeem(assetAddr);
        return _balances[user] < maxIn ? _balances[user] : maxIn;
    }
}

contract Vault is VaultCore {
    function initialize(
        string memory _name,
        string memory _symbol,
        VaultConfiguration memory _cfg,
        address _kclv3
    ) external initializer {
        __ERC20Upgradeable_init(_name, _symbol);
        _config = _cfg;
        kopioCLV3 = IKopioCLV3(_kclv3);
        baseRate = 1 ether;
    }

    /// @inheritdoc IVault
    function allAssets() external view returns (VaultAsset[] memory result) {
        result = new VaultAsset[](assetList.length);
        for (uint256 i; i < assetList.length; i++) {
            result[i] = _assets[assetList[i]];
        }
    }

    /// @inheritdoc IVault
    function assetPrice(address assetAddr) external view returns (uint256) {
        return _price(_assets[assetAddr]);
    }

    /// @inheritdoc IVault
    function getConfig() external view returns (VaultConfiguration memory) {
        return _config;
    }

    /// @inheritdoc IVault
    function assets(address assetAddr) external view returns (VaultAsset memory) {
        return _assets[assetAddr];
    }

    /// @inheritdoc IVault
    function getFees(address assetAddr) public view returns (uint256) {
        return IERC20(assetAddr).balanceOf(address(this)) - _deposits[assetAddr];
    }

    /* ------------------------------- Restricted ------------------------------- */

    function feeWithdraw(address assetAddr) external onlyGovernance {
        IERC20(assetAddr).safeTransfer(_config.feeRecipient, getFees(assetAddr));
    }

    function setBaseRate(uint256 newBaseRate) external onlyGovernance {
        baseRate = newBaseRate;
    }

    function setConfiguration(
        address kclv3,
        address feeRecipient,
        address seqFeed,
        uint96 gracePeriod,
        uint8 oracleDec
    ) external onlyGovernance {
        if (kclv3 != address(0)) kopioCLV3 = IKopioCLV3(kclv3);
        if (gracePeriod != 0) _config.sequencerGracePeriodTime = gracePeriod;
        if (seqFeed != address(0)) _config.sequencerUptimeFeed = seqFeed;
        if (feeRecipient != address(0)) _config.feeRecipient = feeRecipient;
        if (oracleDec != 0) _config.oracleDecimals = oracleDec;
    }

    /// @inheritdoc IVault
    function addAsset(VaultAsset memory cfg) external onlyGovernance returns (VaultAsset memory) {
        address assetAddr = address(cfg.token);
        cfg.decimals = cfg.token.decimals();
        if (_assets[assetAddr].decimals != 0 || cfg.decimals == 0 || cfg.decimals > 18) revert INVALID_ASSET(assetAddr);

        _assets[assetAddr] = cfg;
        assetList.push(assetAddr);

        emit AssetAdded(assetAddr, address(cfg.feed), cfg.staleTime, cfg.maxDeposits);

        return cfg;
    }

    /// @inheritdoc IVault
    function removeAsset(address assetAddr) external onlyGovernance {
        assetList.removeExisting(assetAddr);
        delete _assets[assetAddr];
        emit AssetRemoved(assetAddr);
    }

    /// @inheritdoc IVault
    function setAssetFeed(address assetAddr, address feedAddr, uint24 st) external onlyGovernance {
        _assets[assetAddr].feed = IAggregatorV3(feedAddr);
        _assets[assetAddr].staleTime = st;
        emit OracleSet(assetAddr, feedAddr, st);
    }

    /// @inheritdoc IVault
    function setAssetLimits(address assetAddr, uint248 maxDeposits, bool isEnabled) external onlyGovernance {
        _assets[assetAddr].enabled = isEnabled;
        _assets[assetAddr].maxDeposits = maxDeposits;
    }

    /// @inheritdoc IVault
    function setAssetFees(address assetAddr, uint16 newDepositFee, uint16 newWithdrawFee) external onlyGovernance {
        if (newDepositFee < 100e2) _assets[assetAddr].depositFee = newDepositFee;
        if (newWithdrawFee < 100e2) _assets[assetAddr].withdrawFee = newWithdrawFee;
    }

    /// @inheritdoc IVault
    function setGovernance(address newGovernance) external onlyGovernance {
        _config.pendingGovernance = newGovernance;
    }

    /// @inheritdoc IVault
    function acceptGovernance() external {
        if (msg.sender != _config.pendingGovernance) revert INVALID_SENDER(msg.sender, _config.pendingGovernance);
        _config.governance = _config.pendingGovernance;
        _config.pendingGovernance = address(0);
    }
}

contract VaultUpgrade is Vault {
    function initialize(address kclv3) external reinitializer(3) {
        kopioCLV3 = IKopioCLV3(kclv3);
    }
}
