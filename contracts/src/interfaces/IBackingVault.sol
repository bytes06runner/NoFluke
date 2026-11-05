// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBackingVault {
    /// @notice Sends `amount` of USDC to the arena for this duel. Reverts if the fighter may not be backed.
    function fundStake(address fighter, uint256 duelId, uint256 amount, uint256 fighterOwn, address opponent) external;

    /// @notice Receives the vault's share of a finished duel. The arena transfers `returned` before calling.
    function onSettle(uint256 duelId, address fighter, uint256 returned) external;
}
