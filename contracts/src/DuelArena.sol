// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FightMath as F} from "./FightMath.sol";
import {IBackingVault} from "./interfaces/IBackingVault.sol";
import {IFighterRegistry} from "./interfaces/IFighterRegistry.sol";
import {IReferee} from "./interfaces/IReferee.sol";

interface IERC20Transfer {
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC20Permit {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}

/// @title Duel arena
/// @notice USDC escrow, anchored commit-reveal on a shared slot grid, and permissionless settlement with Pyth proofs.
///         Anyone can settle, so no operator can hide a result. No owner, no setters, no proxy.
contract DuelArena is EIP712, ReentrancyGuard {
    enum Status {
        None,
        Open,
        Active,
        Settled,
        Refunded,
        Cancelled
    }

    struct Duel {
        address a;
        address b;
        uint96 stake;
        bytes32 feedId;
        uint32 sigmaRefPpm;
        int64 c;
        uint64 joinBy;
        uint64 startAt;
        Status status;
        uint96 vaultB; // only the joining side can be vault-funded, so at most one side ever is
    }

    struct Reveal {
        bool done;
        uint8 move;
        uint8 read;
        bool overdrive;
    }

    struct Permit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Timing and money parameters, all from config/params.json.
    struct Params {
        uint64 startDelay;
        uint64 slot;
        uint64 tape;
        uint64 priceWindow;
        uint64 revealGrace;
        uint64 settleGrace;
        uint64 refundGrace;
        uint64 maxJoinWindow;
        uint256 rakeBps;
        uint256 maxStake;
        uint256 unverifiedStakeCap;
        uint256 minOwnStakeBps;
        int256 confCapBps;
    }

    /// @dev One boundary price from a verified Pyth update.
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        bool loaded;
        bool missing;
    }

    /// @dev Working memory for settle, kept in one struct to stay within the stack limit.
    struct SettleCtx {
        uint256 id;
        Duel d;
        F.MatchState m;
        Price[] prices;
        uint256 fee;
        bytes[] updates;
    }

    event DuelCreated(uint256 indexed duelId, address indexed fighterA, address opponent, uint256 stake, bytes32 feedId, uint32 sigmaRefPpm, int64 c, uint64 joinBy);
    event DuelJoined(uint256 indexed duelId, address indexed fighterB, uint64 startAt);
    event DuelCancelled(uint256 indexed duelId);
    event CommitAnchored(uint256 indexed duelId, uint8 round, uint8 side, bytes32 commitHash);
    event AnchorSkipped(uint256 indexed duelId, uint8 round, uint8 side);
    event MoveRevealed(uint256 indexed duelId, uint8 round, uint8 side, uint8 move, uint8 read, bool overdrive);
    event RoundScored(uint256 indexed duelId, uint8 round, int256 z, uint8 moveA, uint8 moveB, bool voided, int256 damage, uint8 loser);
    event DuelSettled(uint256 indexed duelId, uint8 winner, uint8 reason, uint8 rounds, uint256 payout, uint256 rake);
    event DuelRefunded(uint256 indexed duelId);
    event BoundaryVoided(uint256 indexed duelId, uint8 boundary);
    event PaymentDeferred(address indexed to, uint256 amount);
    event Claimed(address indexed to, uint256 amount);

    error WrongStatus();
    error NotFighter();
    error NotRegistered();
    error UnsupportedFeed();
    error StakeTooHigh();
    error NeedsSkilled();
    error SameFamily();
    error AgentCapExceeded();
    error AgentUnbound();
    error BadVaultSplit();
    error NoVault();
    error FighterBusy();
    error BadJoinWindow();
    error JoinClosed();
    error TooEarly();
    error TooLate();
    error BadRound();
    error BadSide();
    error EmptyCommit();
    error AlreadyCommitted();
    error BadCommitSignature();
    error NothingAnchored();
    error NoCommit();
    error RevealTooEarly();
    error AlreadyRevealed();
    error RevealMismatch();
    error NotFinal();
    error MissingPriceUpdate();
    error InsufficientFee();
    error RefundFailed();
    error AlreadyVoided();
    error NotStale();
    error NothingOwed();
    error BadParams();

    bytes32 private constant COMMIT_TYPEHASH = keccak256("Commit(uint256 duelId,uint8 round,bytes32 commitHash)");
    uint256 private constant BPS = 10_000;

    IPyth public immutable pyth;
    address public immutable usdc;
    IFighterRegistry public immutable registry;
    IReferee public immutable referee;
    IBackingVault public immutable vault;
    address public immutable rakeTo;

    uint64 public immutable START_DELAY;
    uint64 public immutable SLOT;
    uint64 public immutable TAPE;
    uint64 public immutable PRICE_WINDOW;
    uint64 public immutable REVEAL_GRACE;
    uint64 public immutable SETTLE_GRACE;
    uint64 public immutable REFUND_GRACE;
    uint64 public immutable MAX_JOIN_WINDOW;
    uint256 public immutable RAKE_BPS;
    uint256 public immutable MAX_STAKE;
    uint256 public immutable UNVERIFIED_STAKE_CAP;
    uint256 public immutable MIN_OWN_STAKE_BPS;
    int256 public immutable CONF_CAP_BPS;

    int256 private immutable HP_START;
    int256 private immutable METER_START;
    int256 private immutable METER_CAP;
    int256 private immutable OVERDRIVE_COST;
    int256 private immutable METER_WIN;
    int256 private immutable METER_LOSS;
    int256 private immutable DAMAGE_BASE;
    int256 private immutable DIFF_CAP;
    int256 private immutable TIE;
    uint8 public immutable REGULAR_ROUNDS;
    uint8 public immutable MAX_ROUNDS;
    int256 private immutable SIGMA_MIN;
    int256 private immutable SIGMA_MAX;
    int256 private immutable PAYOFF_PER_Z;
    int256 private immutable COUNTER_NUM;
    int256 private immutable COUNTER_DEN;

    uint256 public nextDuelId = 1;
    mapping(uint256 => Duel) private _duels;
    mapping(uint256 => mapping(uint8 => mapping(uint8 => bytes32))) private _commits;
    mapping(uint256 => mapping(uint8 => mapping(uint8 => Reveal))) private _reveals;
    mapping(uint256 => mapping(uint8 => bool)) public boundaryVoided;
    mapping(bytes32 => int64) public stormC;
    mapping(address => uint256) public activeDuel;
    mapping(address => uint256) public owed;

    constructor(
        IPyth pyth_,
        address usdc_,
        IFighterRegistry registry_,
        IReferee referee_,
        IBackingVault vault_,
        address rakeTo_,
        Params memory p,
        F.Rules memory r,
        bytes32[] memory feeds,
        int64[] memory cs
    ) {
        // Bounds a config mistake could otherwise silently remove.
        if (
            rakeTo_ == address(0) || p.tape == 0 || p.slot != p.tape || p.priceWindow == 0 || p.priceWindow > p.revealGrace
                || p.settleGrace == 0 || p.settleGrace >= p.refundGrace || p.rakeBps > BPS || p.minOwnStakeBps > BPS
                || p.maxStake == 0 || p.maxStake > type(uint96).max || p.unverifiedStakeCap > p.maxStake || p.confCapBps < 0
                || feeds.length != cs.length
        ) revert BadParams();
        pyth = pyth_;
        usdc = usdc_;
        registry = registry_;
        referee = referee_;
        vault = vault_;
        rakeTo = rakeTo_;
        START_DELAY = p.startDelay;
        SLOT = p.slot;
        TAPE = p.tape;
        PRICE_WINDOW = p.priceWindow;
        REVEAL_GRACE = p.revealGrace;
        SETTLE_GRACE = p.settleGrace;
        REFUND_GRACE = p.refundGrace;
        MAX_JOIN_WINDOW = p.maxJoinWindow;
        RAKE_BPS = p.rakeBps;
        MAX_STAKE = p.maxStake;
        UNVERIFIED_STAKE_CAP = p.unverifiedStakeCap;
        MIN_OWN_STAKE_BPS = p.minOwnStakeBps;
        CONF_CAP_BPS = p.confCapBps;
        HP_START = r.hpStart;
        METER_START = r.meterStart;
        METER_CAP = r.meterCap;
        OVERDRIVE_COST = r.overdriveCost;
        METER_WIN = r.meterWin;
        METER_LOSS = r.meterLoss;
        DAMAGE_BASE = r.damageBase;
        DIFF_CAP = r.diffCap;
        TIE = r.tie;
        REGULAR_ROUNDS = r.regularRounds;
        MAX_ROUNDS = r.maxRounds;
        SIGMA_MIN = r.sigmaMin;
        SIGMA_MAX = r.sigmaMax;
        PAYOFF_PER_Z = r.payoffPerZ;
        COUNTER_NUM = r.counterNum;
        COUNTER_DEN = r.counterDen;
        for (uint256 i; i < feeds.length; ++i) {
            if (cs[i] <= 0) revert BadParams();
            stormC[feeds[i]] = cs[i];
        }
    }

    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return ("NoFlukeArena", "1");
    }

    function _rules() private view returns (F.Rules memory) {
        return F.Rules(
            HP_START, METER_START, METER_CAP, OVERDRIVE_COST, METER_WIN, METER_LOSS, DAMAGE_BASE, DIFF_CAP, TIE,
            REGULAR_ROUNDS, MAX_ROUNDS, SIGMA_MIN, SIGMA_MAX, PAYOFF_PER_Z, COUNTER_NUM, COUNTER_DEN
        );
    }

    // ---------------------------------------------------------------- views

    function duel(uint256 id) external view returns (Duel memory) {
        return _duels[id];
    }

    function commitOf(uint256 id, uint8 round, uint8 side) external view returns (bytes32) {
        return _commits[id][round][side];
    }

    function revealOf(uint256 id, uint8 round, uint8 side) external view returns (Reveal memory) {
        return _reveals[id][round][side];
    }

    /// @notice Round r's tape runs from boundary r - 1 to boundary r.
    function tStart(uint256 id, uint8 round) public view returns (uint64) {
        return _duels[id].startAt + uint64(round) * SLOT;
    }

    function revealDeadline(uint256 id) public view returns (uint64) {
        return tStart(id, MAX_ROUNDS) + TAPE + REVEAL_GRACE;
    }

    function settleDeadline(uint256 id) public view returns (uint64) {
        return revealDeadline(id) + SETTLE_GRACE;
    }

    function commitHash(uint256 id, uint8 round, address fighter, uint8 move, uint8 read, bool overdrive, bytes32 salt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(id, round, fighter, move, read, overdrive, salt));
    }

    function commitDigest(uint256 id, uint8 round, bytes32 hash) public view returns (bytes32) {
        return _hashTypedData(keccak256(abi.encode(COMMIT_TYPEHASH, id, round, hash)));
    }

    // ---------------------------------------------------------------- joining

    function _checkFighter(address fighter, uint256 stake) private view {
        if (!registry.isRegistered(fighter)) revert NotRegistered();
        if (registry.isUnbound(fighter)) revert AgentUnbound();
        if (stake > registry.stakeCapOf(fighter)) revert AgentCapExceeded();
    }

    function _pull(address from, uint256 amount, Permit calldata permit) private {
        if (amount == 0) return;
        if (permit.deadline != 0) {
            // A front-run permit only spends the nonce, and the pull below still works.
            try IERC20Permit(usdc).permit(from, address(this), amount, permit.deadline, permit.v, permit.r, permit.s) {} catch {}
        }
        SafeTransferLib.safeTransferFrom(usdc, from, address(this), amount);
    }

    function _fund(uint256 id, address fighter, address opponent, uint256 stake, uint96 vaultAmount, Permit calldata permit) private {
        if (vaultAmount > stake) revert BadVaultSplit();
        uint256 own = stake - vaultAmount;
        if (vaultAmount > 0) {
            if (address(vault) == address(0)) revert NoVault();
            if ((own * BPS) / stake < MIN_OWN_STAKE_BPS) revert BadVaultSplit();
            vault.fundStake(fighter, id, vaultAmount, own, opponent);
        }
        _pull(fighter, own, permit);
    }

    /// @notice Creates a challenge. `opponent` zero means anyone may join. It is advertised on Arkiv, not here.
    function createDuel(
        bytes32 feedId,
        uint32 sigmaRefPpm,
        uint96 stake,
        address opponent,
        uint64 joinBy,
        Permit calldata permit
    ) external nonReentrant returns (uint256 id) {
        int64 c = stormC[feedId];
        if (c == 0) revert UnsupportedFeed();
        if (int256(uint256(sigmaRefPpm)) < SIGMA_MIN || int256(uint256(sigmaRefPpm)) > SIGMA_MAX) revert F.SigmaBounds();
        if (stake > MAX_STAKE) revert StakeTooHigh();
        if (joinBy <= block.timestamp || joinBy > block.timestamp + MAX_JOIN_WINDOW) revert BadJoinWindow();
        _checkFighter(msg.sender, stake);
        id = nextDuelId++;
        _duels[id] = Duel(msg.sender, opponent, stake, feedId, sigmaRefPpm, c, joinBy, 0, Status.Open, 0);
        _pull(msg.sender, stake, permit);
        emit DuelCreated(id, msg.sender, opponent, stake, feedId, sigmaRefPpm, c, joinBy);
    }

    /// @notice Joins a duel. Rechecks both sides, since either could have changed since the challenge was posted.
    function joinDuel(uint256 id, Permit calldata permit, uint96 vaultAmount) external nonReentrant {
        Duel storage d = _duels[id];
        if (d.status != Status.Open) revert WrongStatus();
        if (block.timestamp > d.joinBy) revert JoinClosed();
        if (d.b != address(0) && d.b != msg.sender) revert NotFighter();
        address a = d.a;
        if (a == msg.sender) revert NotFighter();
        uint256 stake = d.stake;
        _checkFighter(a, stake);
        _checkFighter(msg.sender, stake);
        if (registry.isSameFamily(a, msg.sender)) revert SameFamily();
        // One live duel per fighter, so nobody can hedge moves across duels and settle only the winner.
        if (activeDuel[a] != 0 || activeDuel[msg.sender] != 0) revert FighterBusy();
        if (stake > UNVERIFIED_STAKE_CAP && !(_skilled(a) && _skilled(msg.sender))) revert NeedsSkilled();
        activeDuel[a] = id;
        activeDuel[msg.sender] = id;
        d.b = msg.sender;
        d.status = Status.Active;
        d.vaultB = vaultAmount;
        // Round starts sit on one shared grid, so all duels on a feed share tapes and price updates.
        uint64 earliest = uint64(block.timestamp) + START_DELAY;
        d.startAt = ((earliest + SLOT - 1) / SLOT) * SLOT;
        _fund(id, msg.sender, a, stake, vaultAmount, permit);
        emit DuelJoined(id, msg.sender, d.startAt);
    }

    function _skilled(address fighter) private view returns (bool) {
        IReferee.Verdict memory v = referee.verdictOf(fighter);
        return v.skilled && !v.lapsed;
    }

    function cancel(uint256 id) external nonReentrant {
        Duel storage d = _duels[id];
        if (d.status != Status.Open) revert WrongStatus();
        if (block.timestamp <= d.joinBy) revert TooEarly();
        d.status = Status.Cancelled;
        _pay(d.a, d.stake);
        emit DuelCancelled(id);
    }

    // ---------------------------------------------------------------- commit and reveal

    function _active(uint256 id, uint8 round) private view returns (Duel storage d) {
        d = _duels[id];
        if (d.status != Status.Active) revert WrongStatus();
        if (round == 0 || round > MAX_ROUNDS) revert BadRound();
    }

    function _validCommit(Duel storage d, uint256 id, uint8 round, uint8 side, bytes32 c, bytes memory sig) private view returns (bool) {
        address fighter = side == 0 ? d.a : d.b;
        return ECDSA.tryRecover(commitDigest(id, round, c), sig) == registry.moveKeyOf(fighter);
    }

    /// @notice Batch anchor. A bad or duplicate side is skipped, so one fighter can never make the other forfeit.
    function anchor(uint256 id, uint8 round, bytes32 cA, bytes calldata sigA, bytes32 cB, bytes calldata sigB) external {
        Duel storage d = _active(id, round);
        if (block.timestamp >= tStart(id, round)) revert TooLate();
        bool landed = _tryAnchor(d, id, round, 0, cA, sigA);
        landed = _tryAnchor(d, id, round, 1, cB, sigB) || landed;
        if (!landed) revert NothingAnchored();
    }

    function _tryAnchor(Duel storage d, uint256 id, uint8 round, uint8 side, bytes32 c, bytes memory sig) private returns (bool) {
        if (c == bytes32(0) || _commits[id][round][side] != bytes32(0)) return false;
        if (!_validCommit(d, id, round, side, c, sig)) {
            emit AnchorSkipped(id, round, side);
            return false;
        }
        _commits[id][round][side] = c;
        emit CommitAnchored(id, round, side, c);
        return true;
    }

    /// @notice The strict single-side path, for a fighter whose commit nobody else will forward.
    function anchorOwn(uint256 id, uint8 round, uint8 side, bytes32 c, bytes calldata sig) external {
        Duel storage d = _active(id, round);
        if (side > 1) revert BadSide();
        if (block.timestamp >= tStart(id, round)) revert TooLate();
        if (c == bytes32(0)) revert EmptyCommit();
        if (_commits[id][round][side] != bytes32(0)) revert AlreadyCommitted();
        if (!_validCommit(d, id, round, side, c, sig)) revert BadCommitSignature();
        _commits[id][round][side] = c;
        emit CommitAnchored(id, round, side, c);
    }

    /// @notice Anyone may reveal an opening. An invalid move is stored and forfeits at settle, so it can't block settling.
    function reveal(uint256 id, uint8 round, uint8 side, uint8 move, uint8 read, bool overdrive, bytes32 salt) external {
        Duel storage d = _active(id, round);
        if (side > 1) revert BadSide();
        if (block.timestamp > revealDeadline(id)) revert TooLate();
        bytes32 c = _commits[id][round][side];
        if (c == bytes32(0)) revert NoCommit();
        // An opening must never be public while the opponent can still reply to it.
        if (_commits[id][round][1 - side] == bytes32(0) && block.timestamp < tStart(id, round)) revert RevealTooEarly();
        Reveal storage r = _reveals[id][round][side];
        if (r.done) revert AlreadyRevealed();
        address fighter = side == 0 ? d.a : d.b;
        if (commitHash(id, round, fighter, move, read, overdrive, salt) != c) revert RevealMismatch();
        _reveals[id][round][side] = Reveal(true, move, read, overdrive);
        emit MoveRevealed(id, round, side, move, read, overdrive);
    }

    // ---------------------------------------------------------------- settling

    function _boundaryTime(Duel memory d, uint8 boundary) private view returns (uint64) {
        return d.startAt + (uint64(boundary) + 1) * SLOT;
    }

    /// @dev Loads a boundary's price once, so a round's end and the next round's start share one Pyth verification.
    function _price(SettleCtx memory x, uint8 boundary) private returns (Price memory p) {
        p = x.prices[boundary];
        if (p.loaded) return p;
        p.loaded = true;
        if (boundaryVoided[x.id][boundary]) {
            p.missing = true;
            return p;
        }
        if (boundary >= x.updates.length || x.updates[boundary].length == 0) revert MissingPriceUpdate();
        uint64 t = _boundaryTime(x.d, boundary);
        bytes[] memory one = new bytes[](1);
        one[0] = x.updates[boundary];
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = x.d.feedId;
        uint256 fee = pyth.getUpdateFee(one);
        x.fee += fee;
        if (x.fee > msg.value) revert InsufficientFee();
        PythStructs.PriceFeed[] memory f = pyth.parsePriceFeedUpdatesUnique{value: fee}(one, ids, t, t + PRICE_WINDOW);
        p.price = f[0].price.price;
        p.conf = f[0].price.conf;
        p.expo = f[0].price.expo;
    }

    function _commandOf(uint256 id, uint8 round, uint8 side) private view returns (bool missing, F.Command memory cmd) {
        Reveal storage r = _reveals[id][round][side];
        if (_commits[id][round][side] == bytes32(0)) {
            // A missing commit is final the moment the bell has rung, since no anchor can land later.
            if (block.timestamp < tStart(id, round)) revert NotFinal();
            return (true, cmd);
        }
        if (!r.done) {
            if (block.timestamp <= revealDeadline(id)) revert NotFinal();
            return (true, cmd);
        }
        return (false, F.Command(r.move, r.read, r.overdrive));
    }

    function _scoreRound(SettleCtx memory x, F.Rules memory rules) private {
        uint8 round = x.m.r + 1;
        F.MatchRound memory mr;
        (mr.aMissing, mr.a) = _commandOf(x.id, round, 0);
        (mr.bMissing, mr.b) = _commandOf(x.id, round, 1);
        if (F.isScored(mr)) {
            if (block.timestamp < _boundaryTime(x.d, round) + PRICE_WINDOW) revert NotFinal();
            Price memory p0 = _price(x, round - 1);
            x.prices[round - 1] = p0;
            Price memory p1 = _price(x, round);
            x.prices[round] = p1;
            mr.voided = p0.missing || p1.missing
                || F.isVoid(p0.price, int256(uint256(p0.conf)), p0.expo, p1.price, int256(uint256(p1.conf)), p1.expo, CONF_CAP_BPS);
            mr.p0 = p0.price;
            mr.p1 = p1.price;
        }
        F.RoundResult memory r = F.applyRound(rules, x.m, mr, int256(uint256(x.d.sigmaRefPpm)), x.d.c);
        if (!F.isScored(mr)) {
            _rateForfeits(x.d, mr);
        } else if (!mr.voided) {
            referee.recordRound(x.d.feedId, tStart(x.id, round), mr.p0, mr.p1, x.d.c, x.d.a, mr.a.move, x.d.b, mr.b.move);
        }
        emit RoundScored(x.id, round, r.z, mr.a.move, mr.b.move, mr.voided, r.damage, r.loser);
    }

    function _rateForfeits(Duel memory d, F.MatchRound memory mr) private {
        bool fa = mr.aMissing || !F.validMove(mr.a.move) || !F.validRead(mr.a.read);
        bool fb = mr.bMissing || !F.validMove(mr.b.move) || !F.validRead(mr.b.read);
        if (fa) referee.recordForfeit(d.a);
        if (fb) referee.recordForfeit(d.b);
    }

    /// @notice Settles a duel from verified prices. updates[k] is the Pyth update for boundary k, the start of round k + 1.
    function settle(uint256 id, bytes[] calldata updates) external payable nonReentrant {
        Duel memory d = _duels[id];
        if (d.status != Status.Active) revert WrongStatus();
        F.Rules memory rules = _rules();
        SettleCtx memory x;
        x.id = id;
        x.d = d;
        x.m = F.begin(rules, int256(uint256(d.sigmaRefPpm)));
        x.prices = new Price[](uint256(MAX_ROUNDS) + 1);
        x.updates = updates;
        while (F.needsRound(rules, x.m)) _scoreRound(x, rules);
        _duels[id].status = Status.Settled;
        _release(d);
        (uint256 payout, uint256 rake) = _payOut(id, d, x.m.winner);
        emit DuelSettled(id, x.m.winner, x.m.reason, x.m.r, payout, rake);
        uint256 extra = msg.value - x.fee;
        if (extra > 0) {
            (bool ok,) = msg.sender.call{value: extra}("");
            if (!ok) revert RefundFailed();
        }
    }

    function _release(Duel memory d) private {
        delete activeDuel[d.a];
        delete activeDuel[d.b];
    }

    function _splitToSide(uint256 id, address fighter, uint256 amount, uint96 vaultPart, uint256 stake) private {
        if (vaultPart == 0 || amount == 0) {
            if (vaultPart != 0) vault.onSettle(id, fighter, 0);
            _pay(fighter, amount);
            return;
        }
        // Pro rata, rounding the vault's share down.
        uint256 toVault = (amount * vaultPart) / stake;
        SafeTransferLib.safeTransfer(usdc, address(vault), toVault);
        vault.onSettle(id, fighter, toVault);
        _pay(fighter, amount - toVault);
    }

    function _payOut(uint256 id, Duel memory d, uint8 winner) private returns (uint256 payout, uint256 rake) {
        uint256 stake = d.stake;
        if (winner == 0) {
            _pay(d.a, stake);
            _splitToSide(id, d.b, stake, d.vaultB, stake);
            return (0, 0);
        }
        rake = (2 * stake * RAKE_BPS) / BPS;
        payout = 2 * stake - rake;
        _pay(rakeTo, rake);
        if (winner == 1) {
            _pay(d.a, payout);
            if (d.vaultB != 0) vault.onSettle(id, d.b, 0);
        } else {
            _splitToSide(id, d.b, payout, d.vaultB, stake);
        }
    }

    /// @notice Pays a fighter, or credits them if the token refuses, so no recipient can block settlement.
    function _pay(address to, uint256 amount) private {
        if (amount == 0) return;
        (bool ok, bytes memory ret) = usdc.call(abi.encodeWithSelector(IERC20Transfer.transfer.selector, to, amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) {
            owed[to] += amount;
            emit PaymentDeferred(to, amount);
        }
    }

    function claim() external nonReentrant {
        uint256 amount = owed[msg.sender];
        if (amount == 0) revert NothingOwed();
        owed[msg.sender] = 0;
        SafeTransferLib.safeTransfer(usdc, msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    /// @notice Marks a price boundary as missing, proven by Pyth. Rounds touching it are void; a priced boundary cannot be voided.
    function voidBoundary(uint256 id, uint8 boundary, bytes calldata proof) external payable nonReentrant {
        Duel storage d = _duels[id];
        if (d.status != Status.Active) revert WrongStatus();
        if (boundary > MAX_ROUNDS) revert BadRound();
        if (block.timestamp <= settleDeadline(id)) revert TooEarly();
        if (boundaryVoided[id][boundary]) revert AlreadyVoided();
        uint64 t = _boundaryTime(d, boundary);
        bytes[] memory one = new bytes[](1);
        one[0] = proof;
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = d.feedId;
        uint256 fee = pyth.getUpdateFee(one);
        if (fee > msg.value) revert InsufficientFee();
        // The first update after t must itself be later than the window, or a real price exists.
        PythStructs.PriceFeed[] memory f = pyth.parsePriceFeedUpdatesUnique{value: fee}(one, ids, t, type(uint64).max);
        if (uint64(f[0].price.publishTime) <= t + PRICE_WINDOW) revert NotStale();
        boundaryVoided[id][boundary] = true;
        emit BoundaryVoided(id, boundary);
        uint256 extra = msg.value - fee;
        if (extra > 0) {
            (bool ok,) = msg.sender.call{value: extra}("");
            if (!ok) revert RefundFailed();
        }
    }

    /// @notice Refunds a duel nobody settled. Both fighters are charged forfeits, so refusing to settle a loss never helps.
    function refundExpired(uint256 id) external nonReentrant {
        Duel memory d = _duels[id];
        if (d.status != Status.Active) revert WrongStatus();
        if (block.timestamp <= revealDeadline(id) + REFUND_GRACE) revert TooEarly();
        _duels[id].status = Status.Refunded;
        _release(d);
        for (uint256 i; i < REGULAR_ROUNDS; ++i) {
            referee.recordForfeit(d.a);
            referee.recordForfeit(d.b);
        }
        _pay(d.a, d.stake);
        _splitToSide(id, d.b, d.stake, d.vaultB, d.stake);
        emit DuelRefunded(id);
    }
}
