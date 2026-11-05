// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EIP712} from "solady/utils/EIP712.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ApprovalLib} from "./ApprovalLib.sol";
import {IBackingVault} from "./interfaces/IBackingVault.sol";
import {IFighterRegistry} from "./interfaces/IFighterRegistry.sol";
import {IReferee} from "./interfaces/IReferee.sol";

/// @title Backing vault
/// @notice Backers can only fund fighters the referee has certified, and only after that fighter's human approved it.
///         Funds only ever move to a depositor or the arena. No owner, no setters.
contract BackingVault is IBackingVault, EIP712, ReentrancyGuard {
    uint256 private constant BPS = 10_000;
    uint256 private constant SHARE_OFFSET = 1e6; // virtual shares, which defeat first-depositor share inflation
    uint256 private constant PPS_ONE = 1e18;
    uint256 private constant DAY = 1 days;

    struct Params {
        uint256 maxStakeBps;
        uint256 dailyLossBps;
        uint256 maxDuelsPerDay;
        uint256 fundCooldown;
        uint256 feeBps;
        uint256 minOwnBps;
        uint256 forfeitPause;
    }

    struct Vault {
        uint256 assets;
        uint256 shares;
        uint256 liveDuel;
        uint256 inFlight;
        uint256 highWater;
        uint64 lastEnded;
        uint64 pausedUntil;
        uint8 ringNext;
    }

    struct Funding {
        uint64 at;
        uint192 loss;
    }

    event BackingAllowed(address indexed fighter);
    event Deposited(address indexed fighter, address indexed backer, uint256 assets, uint256 shares);
    event Withdrawn(address indexed fighter, address indexed backer, uint256 assets, uint256 shares);
    event StakeFunded(address indexed fighter, uint256 indexed duelId, uint256 amount, address opponent);
    event StakeSettled(address indexed fighter, uint256 indexed duelId, uint256 staked, uint256 returned);
    event FeeMinted(address indexed fighter, uint256 shares, uint256 profitAssets);
    event AutoStopped(address indexed fighter, uint64 until);

    error NotArena();
    error NotSkilled();
    error BackingNotAllowed();
    error FighterUnbound();
    error DuelLive();
    error ZeroAmount();
    error InsufficientShares();
    error OpponentSkilled();
    error SameFamily();
    error Paused();
    error Cooldown();
    error OwnStakeTooSmall();
    error StakeTooLarge();
    error TooManyDuels();
    error DailyLossCap();
    error UnknownDuel();
    error BadParams();

    address public immutable usdc;
    address public immutable arena;
    IReferee public immutable referee;
    IFighterRegistry public immutable registry;
    address public immutable attester;
    uint256 public immutable MAX_STAKE_BPS;
    uint256 public immutable DAILY_LOSS_BPS;
    uint256 public immutable MAX_DUELS_PER_DAY;
    uint256 public immutable FUND_COOLDOWN;
    uint256 public immutable FEE_BPS;
    uint256 public immutable MIN_OWN_BPS;
    uint256 public immutable FORFEIT_PAUSE;

    mapping(address => Vault) private _vaults;
    mapping(address => mapping(address => uint256)) private _shares;
    mapping(address => mapping(uint256 => Funding)) private _ring;
    mapping(address => bool) public backingAllowed;
    mapping(bytes32 => bool) public approvalUsed;

    constructor(address usdc_, address arena_, IReferee referee_, IFighterRegistry registry_, address attester_, Params memory p) {
        if (
            arena_ == address(0) || attester_ == address(0) || p.maxStakeBps > BPS || p.dailyLossBps > BPS || p.feeBps > BPS
                || p.minOwnBps > BPS || p.maxDuelsPerDay == 0 || p.maxDuelsPerDay > type(uint8).max || p.fundCooldown == 0
                || p.forfeitPause == 0
        ) revert BadParams();
        usdc = usdc_;
        arena = arena_;
        referee = referee_;
        registry = registry_;
        attester = attester_;
        MAX_STAKE_BPS = p.maxStakeBps;
        DAILY_LOSS_BPS = p.dailyLossBps;
        MAX_DUELS_PER_DAY = p.maxDuelsPerDay;
        FUND_COOLDOWN = p.fundCooldown;
        FEE_BPS = p.feeBps;
        MIN_OWN_BPS = p.minOwnBps;
        FORFEIT_PAUSE = p.forfeitPause;
    }

    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return ("NoFlukeBackingVault", "1");
    }

    function approvalDigest(ApprovalLib.Approval memory a) public view returns (bytes32) {
        return _hashTypedData(ApprovalLib.structHash(a));
    }

    function _pps(Vault storage v) private view returns (uint256) {
        return ((v.assets + 1) * PPS_ONE) / (v.shares + SHARE_OFFSET);
    }

    function _certified(address fighter) private view returns (bool) {
        IReferee.Verdict memory x = referee.verdictOf(fighter);
        return x.skilled && !x.lapsed;
    }

    /// @notice The fighter's human opts in with a fresh World approval. Without it nobody can back that fighter.
    function allowBacking(address fighter, ApprovalLib.Approval memory a, bytes calldata sig) external {
        bytes32 digest = approvalDigest(a);
        ApprovalLib.check(a, digest, sig, attester, registry.humanOf(fighter), ApprovalLib.ACTION_ALLOW_BACKING, keccak256(abi.encode(fighter)));
        if (approvalUsed[digest]) revert ApprovalLib.ApprovalUsed();
        approvalUsed[digest] = true;
        backingAllowed[fighter] = true;
        emit BackingAllowed(fighter);
    }

    function deposit(address fighter, uint256 assets) external nonReentrant returns (uint256 shares) {
        Vault storage v = _vaults[fighter];
        if (assets == 0) revert ZeroAmount();
        if (!_certified(fighter)) revert NotSkilled();
        if (registry.isUnbound(fighter)) revert FighterUnbound();
        if (!backingAllowed[fighter]) revert BackingNotAllowed();
        if (v.liveDuel != 0) revert DuelLive();
        shares = (assets * (v.shares + SHARE_OFFSET)) / (v.assets + 1);
        if (shares == 0) revert ZeroAmount();
        v.assets += assets;
        v.shares += shares;
        _shares[fighter][msg.sender] += shares;
        if (v.highWater == 0) v.highWater = _pps(v);
        SafeTransferLib.safeTransferFrom(usdc, msg.sender, address(this), assets);
        emit Deposited(fighter, msg.sender, assets, shares);
    }

    function withdraw(address fighter, uint256 shares) external nonReentrant returns (uint256 assets) {
        Vault storage v = _vaults[fighter];
        if (v.liveDuel != 0) revert DuelLive();
        if (shares == 0) revert ZeroAmount();
        if (_shares[fighter][msg.sender] < shares) revert InsufficientShares();
        assets = (shares * (v.assets + 1)) / (v.shares + SHARE_OFFSET);
        _shares[fighter][msg.sender] -= shares;
        v.shares -= shares;
        v.assets -= assets;
        SafeTransferLib.safeTransfer(usdc, msg.sender, assets);
        emit Withdrawn(fighter, msg.sender, assets, shares);
    }

    /// @inheritdoc IBackingVault
    function fundStake(address fighter, uint256 duelId, uint256 amount, uint256 fighterOwn, address opponent) external nonReentrant {
        if (msg.sender != arena) revert NotArena();
        Vault storage v = _vaults[fighter];
        if (amount == 0) revert ZeroAmount();
        if (!_certified(fighter)) revert NotSkilled();
        if (block.timestamp < v.pausedUntil) revert Paused();
        if (referee.verdictOf(opponent).skilled) revert OpponentSkilled();
        if (registry.isSameFamily(fighter, opponent)) revert SameFamily();
        if (v.liveDuel != 0) revert DuelLive();
        if (v.lastEnded != 0 && block.timestamp < v.lastEnded + FUND_COOLDOWN) revert Cooldown();
        if ((fighterOwn * BPS) / (amount + fighterOwn) < MIN_OWN_BPS) revert OwnStakeTooSmall();
        if (amount * BPS > v.assets * MAX_STAKE_BPS) revert StakeTooLarge();
        (uint256 loss, uint256 count) = rolling(fighter);
        if (count >= MAX_DUELS_PER_DAY) revert TooManyDuels();
        if ((loss + amount) * BPS > DAILY_LOSS_BPS * (v.assets + loss)) revert DailyLossCap();
        v.liveDuel = duelId;
        v.inFlight = amount;
        v.assets -= amount;
        SafeTransferLib.safeTransfer(usdc, arena, amount);
        emit StakeFunded(fighter, duelId, amount, opponent);
    }

    /// @inheritdoc IBackingVault
    function onSettle(uint256 duelId, address fighter, uint256 returned, bool forfeitLoss) external nonReentrant {
        if (msg.sender != arena) revert NotArena();
        Vault storage v = _vaults[fighter];
        if (v.liveDuel != duelId || duelId == 0) revert UnknownDuel();
        uint256 staked = v.inFlight;
        v.liveDuel = 0;
        v.inFlight = 0;
        v.assets += returned;
        v.lastEnded = uint64(block.timestamp);
        uint256 lost = returned < staked ? staked - returned : 0;
        _ring[fighter][v.ringNext] = Funding(uint64(block.timestamp), uint192(lost));
        v.ringNext = uint8((uint256(v.ringNext) + 1) % MAX_DUELS_PER_DAY);
        _chargeFee(fighter, v);
        if (forfeitLoss) {
            // A forfeit scores no rounds, so nothing else would notice a thrown duel.
            v.pausedUntil = uint64(block.timestamp + FORFEIT_PAUSE);
            emit AutoStopped(fighter, v.pausedUntil);
        }
        emit StakeSettled(fighter, duelId, staked, returned);
    }

    function _chargeFee(address fighter, Vault storage v) private {
        uint256 pps = _pps(v);
        if (pps <= v.highWater) return;
        uint256 profit = ((pps - v.highWater) * (v.shares + SHARE_OFFSET)) / PPS_ONE;
        uint256 fee = (profit * FEE_BPS) / BPS;
        if (fee > 0 && fee <= v.assets) {
            uint256 minted = (fee * (v.shares + SHARE_OFFSET)) / (v.assets + 1 - fee);
            v.shares += minted;
            _shares[fighter][fighter] += minted;
            emit FeeMinted(fighter, minted, profit);
        }
        v.highWater = _pps(v);
    }

    /// @notice Losses and funded duels in the last 24 hours, read from a ring that also caps the daily count.
    function rolling(address fighter) public view returns (uint256 loss, uint256 count) {
        for (uint256 i; i < MAX_DUELS_PER_DAY; ++i) {
            Funding storage f = _ring[fighter][i];
            if (f.at != 0 && block.timestamp < f.at + DAY) {
                loss += f.loss;
                ++count;
            }
        }
    }

    function vaultOf(address fighter) external view returns (uint256 assets, uint256 shares, uint256 liveDuel, uint256 inFlight) {
        Vault storage v = _vaults[fighter];
        return (v.assets, v.shares, v.liveDuel, v.inFlight);
    }

    function pausedUntil(address fighter) external view returns (uint64) {
        return _vaults[fighter].pausedUntil;
    }

    function sharesOf(address fighter, address backer) external view returns (uint256) {
        return _shares[fighter][backer];
    }

    function assetsOf(address fighter, address backer) external view returns (uint256) {
        Vault storage v = _vaults[fighter];
        return (_shares[fighter][backer] * (v.assets + 1)) / (v.shares + SHARE_OFFSET);
    }

    /// @notice The price per share above which the fighter earns a fee, scaled by 1e18. It only ever rises.
    function highWaterMark(address fighter) external view returns (uint256) {
        return _vaults[fighter].highWater;
    }
}
