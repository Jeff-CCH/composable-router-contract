// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console2} from 'forge-std/console2.sol';
import {ICREATE3Factory} from 'create3-factory/ICREATE3Factory.sol';

import {RadiantV2FlashLoanCallback} from 'src/callbacks/RadiantV2FlashLoanCallback.sol';
import {DeployBase} from 'script/DeployBase.s.sol';

abstract contract DeployRadiantV2FlashLoanCallback is DeployBase {
    struct RadiantV2FlashLoanCallbackConfig {
        address deployedAddress;
        // constructor params
        address radiantV2Provider;
        uint256 feeRate;
    }

    RadiantV2FlashLoanCallbackConfig internal radiantV2FlashLoanCallbackConfig;

    function _deployRadiantV2FlashLoanCallback(
        address create3Factory,
        address router
    )
        internal
        isRouterAddressZero(router)
        isCREATE3FactoryAddressZero(create3Factory)
        returns (address deployedAddress)
    {
        RadiantV2FlashLoanCallbackConfig memory cfg = radiantV2FlashLoanCallbackConfig;
        deployedAddress = cfg.deployedAddress;
        if (deployedAddress == UNDEPLOYED) {
            ICREATE3Factory factory = ICREATE3Factory(create3Factory);
            bytes32 salt = keccak256('protocolink.radiant.v2.flash.loan.callback.v1');
            bytes memory creationCode = abi.encodePacked(
                type(RadiantV2FlashLoanCallback).creationCode,
                abi.encode(router, cfg.radiantV2Provider, cfg.feeRate)
            );
            deployedAddress = factory.deploy(salt, creationCode);
            console2.log('RadiantV2FlashLoanCallback Deployed:', deployedAddress);
        } else {
            console2.log(
                'RadiantV2FlashLoanCallback Exists. Skip deployment of RadiantV2FlashLoanCallback:',
                deployedAddress
            );
        }
    }
}