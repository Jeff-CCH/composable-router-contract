// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {Router} from 'src/Router.sol';
import {FeeCalculatorBase} from 'src/fees/FeeCalculatorBase.sol';
import {MakerDrawFeeCalculator} from 'src/fees/MakerDrawFeeCalculator.sol';
import {IParam} from 'src/interfaces/IParam.sol';
import {IAgent} from 'src/interfaces/IAgent.sol';
import {IDSProxy} from 'src/interfaces/maker/IDSProxy.sol';
import {MakerCommonUtils, IDSProxyRegistry} from 'test/utils/MakerCommonUtils.sol';

contract MakerDrawFeeCalculatorTest is Test, MakerCommonUtils {
    event FeeCharged(address indexed token, uint256 amount, bytes32 metadata);

    address public constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant ANY_TO_ADDRESS = address(0);
    bytes4 public constant DSPROXY_EXECUTE_SELECTOR = bytes4(keccak256(bytes('execute(address,bytes)')));
    uint256 public constant ETH_LOCK_AMOUNT = 2000 ether;
    uint256 public constant DRAW_DAI_AMOUNT = 20000 ether;
    uint256 public constant DRAW_DATA_START_INDEX = 104;
    uint256 public constant DRAW_DATA_END_INDEX = 264;
    uint256 public constant SIGNER_REFERRAL = 1;
    uint256 public constant BPS_BASE = 10_000;
    bytes32 public constant META_DATA = bytes32(bytes('maker:borrow'));

    address public user;
    address public userDSProxy;
    address public feeCollector;
    Router public router;
    IAgent public userAgent;
    address public userAgentDSProxy;
    address public makerDrawFeeCalculator;
    uint256 public ethCdp;

    // Empty arrays
    address[] public tokensReturnEmpty;
    IParam.Input[] public inputsEmpty;

    function setUp() external {
        user = makeAddr('User');
        feeCollector = makeAddr('FeeCollector');
        address pauser = makeAddr('Pauser');

        // Depoly contracts
        router = new Router(makeAddr('WrappedNative'), address(this), pauser, feeCollector);
        vm.prank(user);
        userAgent = IAgent(router.newAgent());
        makerDrawFeeCalculator = address(new MakerDrawFeeCalculator(address(router), 0, DAI_TOKEN));

        // Setup maker vault
        vm.startPrank(user);
        userDSProxy = IDSProxyRegistry(PROXY_REGISTRY).build();

        // Open ETH Vault
        deal(user, ETH_LOCK_AMOUNT);
        bytes32 ret = IDSProxy(userDSProxy).execute{value: ETH_LOCK_AMOUNT}(
            PROXY_ACTIONS,
            abi.encodeWithSelector(
                0xe685cc04, // selector of "openLockETHAndDraw(address,address,address,address,bytes32,uint256)"
                CDP_MANAGER,
                JUG,
                ETH_JOIN_A,
                DAI_JOIN,
                bytes32(bytes(ETH_JOIN_NAME)),
                DRAW_DAI_AMOUNT
            )
        );
        ethCdp = uint256(ret);
        assertEq(IERC20(DAI_TOKEN).balanceOf(user), DRAW_DAI_AMOUNT);

        // Build user agent's DSProxy
        router.execute(_logicBuildDSProxy(), tokensReturnEmpty, SIGNER_REFERRAL);
        userAgentDSProxy = IDSProxyRegistry(PROXY_REGISTRY).proxies(address(userAgent));

        vm.stopPrank();

        // Setup fee calculator
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = DSPROXY_EXECUTE_SELECTOR;
        address[] memory tos = new address[](1);
        tos[0] = address(ANY_TO_ADDRESS);
        address[] memory feeCalculators = new address[](1);
        feeCalculators[0] = makerDrawFeeCalculator;
        router.setFeeCalculators(selectors, tos, feeCalculators);

        _allowCdp(user, userDSProxy, ethCdp, userAgentDSProxy);

        vm.label(address(router), 'Router');
        vm.label(address(userAgent), 'UserAgent');
        vm.label(feeCollector, 'FeeCollector');
        vm.label(makerDrawFeeCalculator, 'MakerDrawFeeCalculator');

        _makerCommonSetUp();
    }

    function testChargeDrawFee(uint256 amount, uint256 feeRate) external {
        // ETH_LOCK_AMOUNT * price(assume ETH price is 1000) * 60%(LTV)
        uint256 estimateDaiDrawMaxAmount = (ETH_LOCK_AMOUNT * 1000 * 60) / 100;
        amount = bound(amount, 0, estimateDaiDrawMaxAmount);
        feeRate = bound(feeRate, 0, BPS_BASE - 1);

        // Set fee rate
        FeeCalculatorBase(makerDrawFeeCalculator).setFeeRate(feeRate);

        // Encode logic
        IParam.Logic[] memory logics = new IParam.Logic[](1);
        logics[0] = _logicDraw(ethCdp, amount);

        // Get new logics
        (logics, ) = router.getLogicsAndMsgValueWithFee(logics, 0);

        // Prepare assert data
        uint256 expectedNewAmount = FeeCalculatorBase(makerDrawFeeCalculator).calculateAmountWithFee(amount);
        uint256 expectedFee = FeeCalculatorBase(makerDrawFeeCalculator).calculateFee(expectedNewAmount);
        uint256 newAmount = this.decodeDrawAmount(logics[0]);
        uint256 userDaiBalanceBefore = IERC20(DAI_TOKEN).balanceOf(user);
        uint256 feeCollectorBalanceBefore = IERC20(DAI_TOKEN).balanceOf(feeCollector);

        // Execute
        address[] memory tokensReturn = new address[](1);
        tokensReturn[0] = DAI_TOKEN;
        if (expectedFee > 0) {
            vm.expectEmit(true, true, true, true, address(userAgent));
            emit FeeCharged(DAI_TOKEN, expectedFee, META_DATA);
        }
        vm.prank(user);
        router.execute(logics, tokensReturn, SIGNER_REFERRAL);

        assertEq(IERC20(DAI_TOKEN).balanceOf(address(router)), 0);
        assertEq(IERC20(DAI_TOKEN).balanceOf(address(userAgent)), 0);
        assertEq(IERC20(DAI_TOKEN).balanceOf(feeCollector) - feeCollectorBalanceBefore, expectedFee);
        assertEq(IERC20(DAI_TOKEN).balanceOf(user) - userDaiBalanceBefore, amount);
        assertEq(newAmount, expectedNewAmount);
    }

    /// Should be no impact on other maker action
    function testOtherAction() external {
        // Setup
        uint256 freeETHAmount = 1 ether;
        uint256 userEthBalanceBefore = user.balance;
        uint256 feeCollectorEthBalanceBefore = feeCollector.balance;

        // Encode logic
        IParam.Logic[] memory logics = new IParam.Logic[](1);
        logics[0] = _logicFreeETH(userAgentDSProxy, ethCdp, freeETHAmount);

        // Get new logics
        (logics, ) = router.getLogicsAndMsgValueWithFee(logics, 0);

        // Execute
        address[] memory tokensReturn = new address[](1);
        tokensReturn[0] = address(NATIVE);
        vm.prank(user);
        router.execute(logics, tokensReturn, SIGNER_REFERRAL);

        assertEq(address(router).balance, 0);
        assertEq(address(userAgent).balance, 0);
        assertEq(user.balance - userEthBalanceBefore, freeETHAmount);
        assertEq(feeCollector.balance - feeCollectorEthBalanceBefore, 0);
    }

    function decodeDrawAmount(IParam.Logic calldata logic) external pure returns (uint256) {
        bytes calldata data = logic.data;
        (, , , , uint256 amount) = abi.decode(
            data[DRAW_DATA_START_INDEX:DRAW_DATA_END_INDEX],
            (address, address, address, uint256, uint256)
        );

        return amount;
    }

    function _logicBuildDSProxy() internal view returns (IParam.Logic[] memory) {
        IParam.Logic[] memory logics = new IParam.Logic[](1);
        logics[0] = IParam.Logic(
            PROXY_REGISTRY,
            abi.encodeWithSelector(IDSProxyRegistry.build.selector),
            inputsEmpty,
            IParam.WrapMode.NONE,
            address(0),
            address(0)
        );

        return logics;
    }

    function _logicDraw(uint256 cdp, uint256 amount) internal view returns (IParam.Logic memory) {
        // Prepare datas
        bytes memory data = abi.encodeWithSelector(
            IDSProxy.execute.selector,
            PROXY_ACTIONS,
            abi.encodeWithSelector(
                0x9f6f3d5b, // selector of "draw(address,address,address,uint256,uint256)"
                CDP_MANAGER,
                JUG,
                DAI_JOIN,
                cdp,
                amount
            )
        );

        return
            IParam.Logic(
                userAgentDSProxy,
                data,
                inputsEmpty,
                IParam.WrapMode.NONE,
                address(0), // approveTo
                address(0) // callback
            );
    }

    function _logicFreeETH(address dsProxy, uint256 cdp, uint256 amount) internal view returns (IParam.Logic memory) {
        // Prepare data
        bytes memory data = abi.encodeWithSelector(
            IDSProxy.execute.selector,
            PROXY_ACTIONS,
            abi.encodeWithSelector(
                0x7b5a3b43, // selector of "freeETH(address,address,uint256,uint256)"
                CDP_MANAGER,
                ETH_JOIN_A,
                cdp,
                amount
            )
        );

        return
            IParam.Logic(
                dsProxy,
                data,
                inputsEmpty,
                IParam.WrapMode.NONE,
                address(0), // approveTo
                address(0) // callback
            );
    }
}
