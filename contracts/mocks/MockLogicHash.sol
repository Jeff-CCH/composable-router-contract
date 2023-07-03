// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IParam} from '../interfaces/IParam.sol';
import {LogicHash} from '../libraries/LogicHash.sol';

contract MockLogicHash {
    using LogicHash for IParam.LogicBatch;

    function hash(IParam.LogicBatch calldata logicBatch) external pure returns (bytes32) {
        return logicBatch._hash();
    }
}
