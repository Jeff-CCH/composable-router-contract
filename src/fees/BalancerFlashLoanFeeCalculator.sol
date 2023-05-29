// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {FeeCalculatorBase} from './FeeCalculatorBase.sol';
import {Router} from '../Router.sol';
import {IFeeCalculator} from '../interfaces/fees/IFeeCalculator.sol';
import {IParam} from '../interfaces/IParam.sol';

/// @title Balancer flash loan fee calculator
contract BalancerFlashLoanFeeCalculator is IFeeCalculator, FeeCalculatorBase {
    bytes32 internal constant _META_DATA = bytes32(bytes('balancer-v2:flash-loan'));

    constructor(address router_, uint256 feeRate_) FeeCalculatorBase(router_, feeRate_) {}

    function getFees(address, bytes calldata data) external view returns (IParam.Fee[] memory) {
        // Balancer flash loan signature:'flashLoan(address,address[],uint256[],bytes)', selector: 0x5c38449e
        (, address[] memory tokens, uint256[] memory amounts, ) = abi.decode(
            data[4:],
            (address, address[], uint256[], bytes)
        );

        uint256 length = tokens.length;
        IParam.Fee[] memory fees = new IParam.Fee[](length);
        for (uint256 i; i < length; ) {
            fees[i] = IParam.Fee({token: tokens[i], amount: calculateFee(amounts[i]), metadata: _META_DATA});

            unchecked {
                ++i;
            }
        }

        return fees;
    }

    function getDataWithFee(bytes calldata data) external view returns (bytes memory) {
        (address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData) = abi.decode(
            data[4:],
            (address, address[], uint256[], bytes)
        );

        if (userData.length > 0) {
            // Decode data in the flash loan
            IParam.Logic[] memory logics = abi.decode(userData, (IParam.Logic[]));

            // Update logics
            logics = Router(router).getLogicsWithFee(logics);

            // encode
            userData = abi.encode(logics);
        }

        amounts = calculateAmountWithFee(amounts);
        return abi.encodePacked(data[:4], abi.encode(recipient, tokens, amounts, userData));
    }
}
