// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FeeBase} from './FeeBase.sol';
import {IFeeCalculator} from '../interfaces/IFeeCalculator.sol';

contract AaveFlashLoanFeeCalculator is IFeeCalculator, FeeBase {
    bytes32 private constant _META_DATA = bytes32(bytes('Aave:FlashLoan'));

    constructor(address router, uint256 feeRate) FeeBase(router, feeRate) {}

    function getFees(bytes calldata data) external view returns (address[] memory, uint256[] memory, bytes32) {
        // Aave flashloan signature:'flashLoan(address,address[],uint256[],uint256[],address,bytes,uint16)', selector: 0xab9c4b5d
        (, address[] memory tokens, uint256[] memory amounts, , , , ) = abi.decode(
            data[4:],
            (address, address[], uint256[], uint256[], address, bytes, uint16)
        );
        return (tokens, calculateFee(amounts), _META_DATA);
    }

    function getDataWithFee(bytes calldata data) external view returns (bytes memory) {
        (
            address receiverAddress,
            address[] memory assets,
            uint256[] memory amounts,
            uint256[] memory modes,
            address onBehalfOf,
            bytes memory params,
            uint16 referralCode
        ) = abi.decode(data[4:], (address, address[], uint256[], uint256[], address, bytes, uint16));

        amounts = calculateAmountWithFee(amounts);
        return
            abi.encodePacked(
                data[:4],
                abi.encode(receiverAddress, assets, amounts, modes, onBehalfOf, params, referralCode)
            );
    }
}
