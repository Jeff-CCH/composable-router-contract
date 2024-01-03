// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeployRouter} from './DeployRouter.s.sol';
import {DeployMorphoFlashLoanCallback} from './callbacks/DeployMorphoFlashLoanCallback.s.sol';

contract DeployGoerli is DeployRouter, DeployMorphoFlashLoanCallback {
    address public constant DEPLOYER = 0xBcb909975715DC8fDe643EE44b89e3FD6A35A259;
    address public constant OWNER = 0xBcb909975715DC8fDe643EE44b89e3FD6A35A259;
    address public constant PAUSER = 0xBcb909975715DC8fDe643EE44b89e3FD6A35A259;
    address public constant DEFAULT_COLLECTOR = 0xBcb909975715DC8fDe643EE44b89e3FD6A35A259;
    address public constant CREATE3_FACTORY = 0xFa3e9a110E6975ec868E9ed72ac6034eE4255B64;

    /// @notice Set up deploy parameters and deploy contracts whose `deployedAddress` equals `UNDEPLOYED`.
    function setUp() external {
        routerConfig = RouterConfig({
            deployedAddress: 0xDec80E988F4baF43be69c13711453013c212feA8,
            wrappedNative: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6,
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            deployer: DEPLOYER,
            owner: OWNER,
            pauser: PAUSER,
            defaultCollector: DEFAULT_COLLECTOR,
            signer: 0xffFf5a88840FF1f168E163ACD771DFb292164cFA,
            feeRate: 20
        });

        morphoFlashLoanCallbackConfig = MorphoFlashLoanCallbackConfig({
            deployedAddress: 0x24D5b6b712D1f0D0B628E21E39dBaDde3f28C56e,
            morpho: 0x64c7044050Ba0431252df24fEd4d9635a275CB41,
            feeRate: 5
        });
    }

    function _run() internal override {
        // router
        address deployedRouterAddress = _deployRouter(CREATE3_FACTORY);

        // callback
        _deployMorphoFlashLoanCallback(CREATE3_FACTORY, deployedRouterAddress);
    }
}
