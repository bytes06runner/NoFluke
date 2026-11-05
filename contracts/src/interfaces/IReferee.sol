// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFamilySize {
    function familySize(address fighter) external view returns (uint256);
}

interface IReferee {
    struct Params {
        uint256 alphaInv;
        int256 zClip;
        int256 delta;
        int256 payoffPerZ;
        uint256 habitHorizon;
        uint256 habitShortHorizon;
        uint256 meanHorizon;
        uint256 meanShortHorizon;
        uint256 sigmaHorizon;
        uint256 kappa;
        int256 m;
        uint256 lambdaMax;
        uint256 onsBeta;
        uint256 lapseLambda;
        uint256 lapseA;
        int256 lapseEdgeFloor;
        uint256 sigmaMinPpm;
        uint64 tapeS;
        uint256 rankDepth;
    }

    /// @notice One fighter's result, as returned by `verdictOf`.
    struct Verdict {
        bool skilled;
        bool lapsed;
        int256 logW;
        int256 lnBar;
        uint32 rounds;
        uint256 lambda;
        uint256 kAtCert;
    }

    event Rated(address indexed fighter, bytes32 indexed feedId, int256 v, int256 logW, uint256 lambda, uint32 rounds);
    event Certified(address indexed fighter, uint256 k, int256 logW);
    event Lapsed(address indexed fighter);

    error NotArena();
    error UnknownFeed();
    error BadMove();
    error BadParams();

    function recordRound(
        bytes32 feedId,
        uint64 tStart,
        int256 p0,
        int256 p1,
        int256 c,
        address fighterA,
        uint8 moveA,
        address fighterB,
        uint8 moveB
    ) external;

    function recordForfeit(address fighter) external;

    function verdictOf(address fighter) external view returns (Verdict memory);

    function topFighter(bytes32 feedId, uint256 rank) external view returns (address);
}
