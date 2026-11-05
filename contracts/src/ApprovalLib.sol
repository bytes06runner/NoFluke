// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {EIP712} from "solady/utils/EIP712.sol";

/// @notice The World backend's signed approval: proof that a human freshly approved one exact protected action.
library ApprovalLib {
    uint8 internal constant ACTION_ENROLL = 1;
    uint8 internal constant ACTION_ALLOW_BACKING = 2;
    uint8 internal constant ACTION_RAISE_CAP = 3;

    bytes32 internal constant APPROVAL_TYPEHASH =
        keccak256("Approval(address human,uint8 action,bytes32 paramsHash,uint64 expiry,uint256 nonce)");

    struct Approval {
        address human;
        uint8 action;
        bytes32 paramsHash;
        uint64 expiry;
        uint256 nonce;
    }

    error ApprovalExpired();
    error ApprovalUsed();
    error BadApproval();

    function structHash(Approval memory a) internal pure returns (bytes32) {
        return keccak256(abi.encode(APPROVAL_TYPEHASH, a.human, a.action, a.paramsHash, a.expiry, a.nonce));
    }

    /// @notice Checks everything about an approval except single use, which the caller records.
    function check(
        Approval memory a,
        bytes32 digest,
        bytes memory sig,
        address signer,
        address human,
        uint8 action,
        bytes32 paramsHash
    ) internal view {
        if (block.timestamp > a.expiry) revert ApprovalExpired();
        if (a.human != human || a.action != action || a.paramsHash != paramsHash) revert BadApproval();
        if (ECDSA.tryRecover(digest, sig) != signer) revert BadApproval();
    }
}
