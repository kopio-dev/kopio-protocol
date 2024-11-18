// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "scripts/tasks/Periphery.s.sol";
import {VaultUpgrade} from "vault/Vault.sol";
import {CLV3Initializer} from "scripts/utils/payloads/CLV3Payload.sol";

contract Core is Periphery {
    using Utils for *;
    using Log for *;

    function setUp() public virtual {
        useDefaultConfig("KCLV3");
        // useForkConfig("KCLV3-stage");
    }

    function execUpgrade() public broadcasted(sender) {
        Log.sr();

        // deploy the clv3
        deployCLV3(sender);

        // upgrade diamond
        upgradeDiamond(protocolAddr);

        // upgrade core contracts
        upgradeCore();

        // misc
        deployData(sender);

        Log.sr();
    }

    function upgradeDiamond(address diamond) public {
        Log.clg("\n\n  [DIAMOND-CUT] Diamond @", diamond);

        cutterBase(diamond, CreateMode.Create2);
        setInitializer(address(new CLV3Initializer(address(newKopioCLV3))), CLV3Initializer.run.selector);

        diamondCutFull("CLV3-DIAMOND", "./src/contracts/facets/*.sol");

        Log.clg("[DIAMOND-CUT-COMPLETE] Diamond @", diamond);
    }

    function upgradeCore() internal {
        Log.clg("\n\n  [BATCH-UPGRADE]");

        // prepare core contracts batch upgrade
        upgradeOne(oneAddr);
        upgradeVault(vaultAddr);
        upgradeMulticall(multicallAddr);

        // execute core contracts batch upgrade
        uint256 upgrades = execFactoryBatch().length;

        Log.clg(string.concat("[BATCH-UPGRADE-COMPLETE] Upgraded ", upgrades.str(), " contracts."));
    }

    function upgradeVault(address proxy) public {
        setDeploy("", type(VaultUpgrade).creationCode, abi.encodeCall(VaultUpgrade.initialize, (address(newKopioCLV3))));
        upgradeBatch("Vault", proxy);
        Log.clg("[UPGRADE-PREPARED] Vault @", proxy);
    }

    function upgradeOne(address proxy) public {
        setDeploy(type(ONE).creationCode);
        upgradeBatch("ONE", proxy);
        Log.clg("[UPGRADE-PREPARED] One @", proxy);
    }

    function deployKopioAsset(string memory name, string memory symbol, address underlying, address admin, address treasury) internal {
        Meta.Result memory meta = Meta.getKopioAsset(factoryAddr, name, symbol);

        setDeploy("", type(Kopio).creationCode, abi.encodeCall(Kopio.initialize, (meta.name, meta.symbol, admin, protocolAddr, underlying, treasury, 0, 0)));
        deployBatch(meta.symbol, meta.salts.kopio, CreateMode.Proxy3);

        setDeploy(abi.encode(meta.addr.proxy), type(KopioShare).creationCode, abi.encodeCall(KopioShare.initialize, (meta.skName, meta.skSymbol, admin)));
        deployBatch(meta.skSymbol, meta.salts.share, CreateMode.Proxy3);

        execFactoryBatch();

        Log.br();
        Log.clg("[NEW-PROXY] Kopio Asset @", meta.addr.proxy);
        Log.clg("[NEW-PROXY] Kopio Asset Share @", meta.addr.skProxy);
        Log.br();
    }
}
