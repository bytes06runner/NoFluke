// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {IReferee} from "../../src/interfaces/IReferee.sol";

/// @dev Reads the referee's parameters and feeds from config/params.json.
library ConfigReader {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function u(string memory json, string memory key) internal pure returns (uint256) {
        return VM.parseJsonUint(json, key);
    }

    function i(string memory json, string memory key) internal pure returns (int256) {
        return VM.parseJsonInt(json, key);
    }

    function params() internal view returns (string memory) {
        return VM.readFile("../config/params.json");
    }

    function refereeParams(string memory j) internal pure returns (IReferee.Params memory p) {
        p.alphaInv = u(j, ".referee.alphaInv");
        p.zClip = i(j, ".referee.zClipWad");
        p.delta = i(j, ".referee.deltaPointsWad");
        p.payoffPerZ = i(j, ".match.payoffPerZ");
        p.habitHorizon = u(j, ".referee.habitHorizon");
        p.habitShortHorizon = u(j, ".referee.habitShortHorizon");
        p.meanHorizon = u(j, ".referee.meanHorizon");
        p.meanShortHorizon = u(j, ".referee.meanShortHorizon");
        p.sigmaHorizon = u(j, ".referee.sigmaHorizon");
        p.kappa = u(j, ".referee.kappaWad");
        p.m = i(j, ".referee.mPointsWad");
        p.lambdaMax = u(j, ".referee.lambdaMaxWad");
        p.onsBeta = u(j, ".referee.onsBetaWad");
        p.lapseLambda = u(j, ".referee.lapseLambdaWad");
        p.lapseA = u(j, ".referee.lapseA");
        p.lapseEdgeFloor = i(j, ".referee.lapseEdgeFloorWad");
        p.sigmaMinPpm = u(j, ".match.sigmaMinPpm");
        p.tapeS = uint64(u(j, ".timing.tapeS"));
        p.rankDepth = u(j, ".referee.rankDepth");
    }

    function feeds(string memory j) internal pure returns (bytes32[] memory ids, uint256[] memory sigmas) {
        string[] memory order = VM.parseJsonStringArray(j, ".feeds.order");
        ids = new bytes32[](order.length);
        sigmas = new uint256[](order.length);
        for (uint256 n; n < order.length; ++n) {
            string memory key = string.concat('.feeds.entries["', order[n], '"]');
            ids[n] = VM.parseJsonBytes32(j, string.concat(key, ".id"));
            sigmas[n] = VM.parseJsonUint(j, string.concat(key, ".sigmaInitPpm"));
        }
    }
}
