// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFamilySize} from "../../src/interfaces/IReferee.sol";

/// @dev Test double: lets a test set each fighter's family size.
contract MockFamily is IFamilySize {
    mapping(address => uint256) public size;

    function set(address fighter, uint256 k) external {
        size[fighter] = k;
    }

    function familySize(address fighter) external view returns (uint256) {
        return size[fighter];
    }
}
