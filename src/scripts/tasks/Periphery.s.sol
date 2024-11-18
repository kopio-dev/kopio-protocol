// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// solhint-disable no-empty-blocks, reason-string, state-visibility, no-unused-import
import {KopioMulticall, IKopioMulticall} from "periphery/KopioMulticall.sol";
import {KopioCLV3, IKopioCLV3} from "periphery/KopioCLV3.sol";
import {ONE} from "asset/ONE.sol";
import {Kopio} from "asset/Kopio.sol";
import {KopioShare} from "asset/KopioShare.sol";
import "scripts/utils/Task.s.sol";

contract Periphery is Task {
    using Log for *;

    KopioCLV3 newKopioCLV3;
    DataV3 newDataV3;
    KopioMulticall newMulticall;

    function _deployMulticall() public broadcastedById(0) {
        newMulticall = new KopioMulticall(address(0), oneAddr);
        newMulticall.initialize(routerv3Addr, wethAddr, pythAddr, safe);

        Log.clg("[NEW-CONTRACT] @", address(newMulticall));
    }

    function deployCLV3(address owner) public rebroadcasted(owner) {
        bytes32 salt = 0x905ccc5f1bf15a696e83f871163c4753e500b653ca82273b7bfad8045d85a470;
        previewProxy3(salt);

        setDeploy(type(KopioCLV3).creationCode, abi.encodeCall(KopioCLV3.initialize, (owner)));

        newKopioCLV3 = KopioCLV3(deploy("KopioCLV3", salt, CreateMode.Proxy3).proxy);
        Log.clg("[NEW-PROXY] CLV3 @", address(newKopioCLV3));
    }

    function deployData(address owner) public rebroadcasted(owner) {
        bytes32 salt = 0x2d55c72dde02d9c73f1cc28c4211a63abd95cb94c1ddfdee3680f3d455d6c959;
        previewProxy3(salt);

        setDeploy(type(DataV3).creationCode, abi.encodeCall(DataV3.setOwner, (owner, true)));

        newDataV3 = DataV3(deploy("DataV3", salt, CreateMode.Proxy3).proxy);
        Log.clg("[NEW-PROXY] DataV3 @", address(newDataV3));

        newDataV3.setOracles(extDataOracles());
    }

    function upgradeCLV3(address proxy) public {
        setDeploy(type(KopioCLV3).creationCode);
        upgradeBatch("KopioCLV3", proxy);

        Log.clg("[UPGRADE-PREPARED] CLV3 @", proxy);
    }

    function upgradeMulticall(address proxy) public {
        setDeploy(abi.encode(address(protocolAddr), address(oneAddr)), type(KopioMulticall).creationCode, "");
        upgradeBatch("Multicall", proxy);

        Log.clg("[UPGRADE-PREPARED] Multicall @", proxy);
    }

    function upgradeData(address proxy) public {
        setDeploy(type(DataV3).creationCode);
        upgrade("DataV3", proxy);
        DataV3(proxy).setOracles(extDataOracles());

        Log.clg("[UPGRADE] DataV3 @", proxy);
    }
}

function extDataOracles() pure returns (IData.Oracles[] memory res) {
    res = new IData.Oracles[](4);

    res[0] = IData.Oracles({
        addr: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
        clFeed: 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7,
        pythId: bytes32(0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b),
        invertPyth: false,
        ext: true
    });

    res[1] = IData.Oracles({
        addr: 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
        clFeed: 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB,
        pythId: bytes32(0xb0948a5e5313200c632b51bb5ca32f6de0d36e9950a942d19751e833f70dabfd),
        invertPyth: false,
        ext: true
    });

    res[2] = IData.Oracles({
        addr: 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a,
        clFeed: 0xDB98056FecFff59D032aB628337A4887110df3dB,
        pythId: bytes32(0xb962539d0fcb272a494d65ea56f94851c2bcf8823935da05bd628916e2e9edbf),
        invertPyth: false,
        ext: true
    });
    res[3] = IData.Oracles({
        addr: 0x6985884C4392D348587B19cb9eAAf157F13271cd,
        clFeed: 0x1940fEd49cDBC397941f2D336eb4994D599e568B,
        pythId: bytes32(0x3bd860bea28bf982fa06bcf358118064bb114086cc03993bd76197eaab0b8018),
        invertPyth: false,
        ext: true
    });
}
