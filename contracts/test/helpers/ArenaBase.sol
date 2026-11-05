// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PythErrors} from "@pythnetwork/pyth-sdk-solidity/PythErrors.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {DuelArena} from "../../src/DuelArena.sol";
import {FighterRegistry} from "../../src/FighterRegistry.sol";
import {FightMath as F} from "../../src/FightMath.sol";
import {Referee} from "../../src/Referee.sol";
import {IBackingVault} from "../../src/interfaces/IBackingVault.sol";
import {IFamilySize, IReferee} from "../../src/interfaces/IReferee.sol";
import {ConfigReader} from "./ConfigReader.sol";

/// @dev Pyth for unit tests, with the real uniqueness rule. The SDK's MockPyth does not enforce it in
///      parsePriceFeedUpdatesUnique, so tests built on that mock would pass while the rule is untested.
contract StrictMockPyth {
    uint256 public immutable fee;

    constructor(uint256 fee_) {
        fee = fee_;
    }

    function getUpdateFee(bytes[] calldata updates) external view returns (uint256) {
        return updates.length * fee;
    }

    function createPriceFeedUpdateData(bytes32 id, int64 price, uint64 conf, int32 expo, int64 emaPrice, uint64 emaConf, uint64 publishTime, uint64 prevPublishTime)
        external
        pure
        returns (bytes memory)
    {
        PythStructs.PriceFeed memory f;
        f.id = id;
        f.price = PythStructs.Price(price, conf, expo, publishTime);
        f.emaPrice = PythStructs.Price(emaPrice, emaConf, expo, publishTime);
        return abi.encode(f, prevPublishTime);
    }

    function parsePriceFeedUpdatesUnique(bytes[] calldata updates, bytes32[] calldata ids, uint64 minTime, uint64 maxTime)
        external
        payable
        returns (PythStructs.PriceFeed[] memory feeds)
    {
        if (msg.value < updates.length * fee) revert PythErrors.InsufficientFee();
        (PythStructs.PriceFeed memory f, uint64 prev) = abi.decode(updates[0], (PythStructs.PriceFeed, uint64));
        uint256 t = f.price.publishTime;
        if (f.id != ids[0] || t < minTime || t > maxTime || prev >= minTime) revert PythErrors.PriceFeedNotFoundWithinRange();
        feeds = new PythStructs.PriceFeed[](1);
        feeds[0] = f;
    }
}

/// @dev Test token with permit, and a blacklist like USDC's.
contract MockUSDC is ERC20 {
    mapping(address => bool) public blacklisted;

    function name() public pure override returns (string memory) {
        return "Mock USDC";
    }

    function symbol() public pure override returns (string memory) {
        return "mUSDC";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlacklisted(address who, bool on) external {
        blacklisted[who] = on;
    }

    function _beforeTokenTransfer(address, address to, uint256) internal view override {
        require(!blacklisted[to], "blacklisted");
    }
}

/// @dev Deploys the contracts from config/params.json, and plays a duel step by step.
abstract contract ArenaBase is Test {
    uint8 constant UP = 0;
    uint8 constant DOWN = 1;
    uint8 constant GUARD = 2;
    uint8 constant BURST = 3;
    int64 constant P0 = 10_000_000_000;
    int32 constant EXPO = -8;
    uint96 constant STAKE = 1_000_000;
    uint32 constant SIGMA = 1000;

    StrictMockPyth pyth;
    MockUSDC usdc;
    FighterRegistry reg;
    Referee ref;
    DuelArena arena;
    bytes32 feed;
    address rake = address(0xCAFE);
    address registrar = address(0xEEEE);

    uint256 attesterKey = 0xA77E;
    uint256 aKey = 0xA1;
    uint256 bKey = 0xB1;
    uint256 cKey = 0xC1;
    uint256 aMove = 0xA2;
    uint256 bMove = 0xB2;
    uint256 cMove = 0xC2;
    address a;
    address b;
    address c;
    DuelArena.Permit noPermit;
    uint64 slot;
    uint64 window;
    uint256 nextNullifier = 1000;

    function _params(string memory j) internal pure returns (DuelArena.Params memory p) {
        p = DuelArena.Params({
            startDelay: uint64(vm.parseJsonUint(j, ".timing.startDelayS")),
            slot: uint64(vm.parseJsonUint(j, ".timing.slotS")),
            tape: uint64(vm.parseJsonUint(j, ".timing.tapeS")),
            priceWindow: uint64(vm.parseJsonUint(j, ".timing.priceWindowS")),
            revealGrace: uint64(vm.parseJsonUint(j, ".timing.revealGraceS")),
            settleGrace: uint64(vm.parseJsonUint(j, ".timing.settleGraceS")),
            refundGrace: uint64(vm.parseJsonUint(j, ".timing.refundGraceS")),
            maxJoinWindow: uint64(vm.parseJsonUint(j, ".timing.joinDeadlineS")),
            rakeBps: vm.parseJsonUint(j, ".stakes.rakeBps"),
            maxStake: vm.parseJsonUint(j, ".stakes.maxStakeUsdc6"),
            unverifiedStakeCap: vm.parseJsonUint(j, ".stakes.unverifiedCapUsdc6"),
            minOwnStakeBps: vm.parseJsonUint(j, ".vault.minOwnBps"),
            confCapBps: vm.parseJsonInt(j, ".voidRule.confCapBps")
        });
    }

    function _rules(string memory j) internal pure returns (F.Rules memory) {
        return F.Rules({
            hpStart: vm.parseJsonInt(j, ".match.hpStart"),
            meterStart: vm.parseJsonInt(j, ".match.meterStart"),
            meterCap: vm.parseJsonInt(j, ".match.meterCap"),
            overdriveCost: vm.parseJsonInt(j, ".match.overdriveCost"),
            meterWin: vm.parseJsonInt(j, ".match.meterWin"),
            meterLoss: vm.parseJsonInt(j, ".match.meterLoss"),
            damageBase: vm.parseJsonInt(j, ".match.damageBase"),
            diffCap: vm.parseJsonInt(j, ".match.damageDiffCapPoints") * F.WAD,
            tie: vm.parseJsonInt(j, ".match.tiePoints") * F.WAD,
            regularRounds: uint8(vm.parseJsonUint(j, ".match.regularRounds")),
            maxRounds: uint8(vm.parseJsonUint(j, ".match.maxRounds")),
            sigmaMin: vm.parseJsonInt(j, ".match.sigmaMinPpm"),
            sigmaMax: vm.parseJsonInt(j, ".match.sigmaMaxPpm"),
            payoffPerZ: vm.parseJsonInt(j, ".match.payoffPerZ"),
            counterNum: vm.parseJsonInt(j, ".match.counterHitNumerator"),
            counterDen: vm.parseJsonInt(j, ".match.counterHitDenominator")
        });
    }

    function _deploy(IBackingVault vault) internal {
        vm.warp(1_800_000_000);
        a = vm.addr(aKey);
        b = vm.addr(bKey);
        c = vm.addr(cKey);
        string memory j = ConfigReader.params();
        (bytes32[] memory feeds, uint256[] memory sigmas) = ConfigReader.feeds(j);
        feed = feeds[0];
        pyth = new StrictMockPyth(1);
        usdc = new MockUSDC();
        reg = new FighterRegistry(vm.addr(attesterKey), registrar, vm.parseJsonUint(j, ".stakes.maxStakeUsdc6"));
        address arenaAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        ref = new Referee(arenaAddress, IFamilySize(address(reg)), ConfigReader.refereeParams(j), feeds, sigmas);
        int64[] memory cs = new int64[](feeds.length);
        for (uint256 i; i < feeds.length; ++i) cs[i] = 486e15;
        arena = new DuelArena(IPyth(address(pyth)), address(usdc), reg, IReferee(address(ref)), vault, rake, _params(j), _rules(j), feeds, cs);
        assertEq(address(arena), arenaAddress);
        slot = arena.SLOT();
        window = arena.PRICE_WINDOW();
        _human(a, aMove);
        _human(b, bMove);
        _human(c, cMove);
    }

    function _human(address who, uint256 moveKeyPk) internal {
        uint256 n = nextNullifier++;
        uint64 expiry = uint64(block.timestamp + 60);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterKey, reg.attestationDigest(who, n, expiry));
        vm.prank(who);
        reg.registerHuman(vm.addr(moveKeyPk), n, expiry, abi.encodePacked(r, s, v));
        usdc.mint(who, 1_000 * uint256(STAKE));
        vm.prank(who);
        usdc.approve(address(0), 0);
    }

    function _approve(address who) internal {
        vm.prank(who);
        usdc.approve(address(arena), type(uint256).max);
    }

    function _create(address who, uint96 stake, address opponent) internal returns (uint256 id) {
        _approve(who);
        uint64 joinBy = uint64(block.timestamp + arena.MAX_JOIN_WINDOW());
        vm.prank(who);
        id = arena.createDuel(feed, SIGMA, stake, opponent, joinBy, noPermit);
    }

    function _join(address who, uint256 id) internal {
        _approve(who);
        vm.prank(who);
        arena.joinDuel(id, noPermit, 0);
    }

    function _duel(uint96 stake) internal returns (uint256 id) {
        id = _create(a, stake, address(0));
        _join(b, id);
    }

    function _hash(uint256 id, uint8 round, address who, uint8 move, uint8 read, bool od) internal view returns (bytes32) {
        return arena.commitHash(id, round, who, move, read, od, bytes32(uint256(round)));
    }

    function _sig(uint256 id, uint8 round, bytes32 h, uint256 pk) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, arena.commitDigest(id, round, h));
        return abi.encodePacked(r, s, v);
    }

    function _anchorBoth(uint256 id, uint8 round, uint8 ma, uint8 mb) internal {
        vm.warp(arena.tStart(id, round) - 1);
        bytes32 ca = _hash(id, round, a, ma, 0, false);
        bytes32 cb = _hash(id, round, b, mb, 0, false);
        arena.anchor(id, round, ca, _sig(id, round, ca, aMove), cb, _sig(id, round, cb, bMove));
    }

    function _reveal(uint256 id, uint8 round, uint8 side, uint8 move) internal {
        arena.reveal(id, round, side, move, 0, false, bytes32(uint256(round)));
    }

    /// @dev Anchors and reveals one round for both sides.
    function _play(uint256 id, uint8 round, uint8 ma, uint8 mb) internal {
        _anchorBoth(id, round, ma, mb);
        _reveal(id, round, 0, ma);
        _reveal(id, round, 1, mb);
    }

    /// @dev Price update for boundary k of a duel, published exactly on the boundary.
    function _update(uint256 id, uint8 k, int64 price) internal view returns (bytes memory) {
        uint64 t = arena.tStart(id, k + 1);
        return pyth.createPriceFeedUpdateData(feed, price, 1, EXPO, price, 1, t, t - 1);
    }

    function _fee(bytes[] memory u) internal view returns (uint256 total) {
        bytes[] memory one = new bytes[](1);
        for (uint256 i; i < u.length; ++i) {
            if (u[i].length == 0) continue;
            one[0] = u[i];
            total += pyth.getUpdateFee(one);
        }
    }

    /// @dev Builds updates so round r moves by bump[r - 1] from the previous boundary's price.
    function _updates(uint256 id, int64[] memory bumps) internal view returns (bytes[] memory u) {
        u = new bytes[](bumps.length + 1);
        int64 p = P0;
        u[0] = _update(id, 0, p);
        for (uint256 i; i < bumps.length; ++i) {
            p += bumps[i];
            u[i + 1] = _update(id, uint8(i + 1), p);
        }
    }

    function _settle(uint256 id, bytes[] memory u) internal {
        vm.warp(arena.revealDeadline(id) + 1);
        arena.settle{value: _fee(u)}(id, u);
    }

    function _bumps(uint256 n, int64 bump) internal pure returns (int64[] memory x) {
        x = new int64[](n);
        for (uint256 i; i < n; ++i) x[i] = bump;
    }

    receive() external payable {}
}
