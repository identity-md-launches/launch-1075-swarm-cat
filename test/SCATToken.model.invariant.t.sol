// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SCATToken} from "../src/SCATToken.sol";
import {TestBase} from "./TestBase.sol";

/// @dev A closed set of holders with an independent ledger. Bounds and expected outcomes use
/// only the ledger, never the token's reported balances or allowances. Rejected calls are caught
/// so Foundry can keep exploring; an unexpected outcome reverts the handler and fails the run.
contract SCATLedgerHandler is TestBase {
    uint256 public constant SUPPLY = 1_000_000_000e18;
    SCATToken public immutable token;
    address[6] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public successfulCalls;
    uint256 public rejectedCalls;

    constructor() {
        actors = [
            address(this),
            0x000000000004444c5dc75cB358380D2e3dE08A90,
            address(0xD157),
            address(0xA11CE),
            address(0xB0B),
            address(0)
        ];
        token = new SCATToken();
        expectedBalance[address(this)] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = _edgeAmount(amountSeed, expectedBalance[from]);
        bool shouldSucceed = from != address(0) && to != address(0) && amount <= expectedBalance[from];

        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(SCATToken.transfer, (to, amount)));
        _checkResult(success, result, shouldSucceed);
        if (shouldSucceed) _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = _edgeAmount(amountSeed, SUPPLY);
        bool shouldSucceed = owner != address(0) && spender != address(0);

        vm.prank(owner);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(SCATToken.approve, (spender, amount)));
        _checkResult(success, result, shouldSucceed);
        if (shouldSucceed) expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 held = expectedBalance[owner];
        uint256 amount = _edgeAmount(amountSeed, held < approved ? held : approved);
        bool shouldSucceed = owner != address(0) && to != address(0) && amount <= held && amount <= approved;

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(SCATToken.transferFrom, (owner, to, amount)));
        _checkResult(success, result, shouldSucceed);
        if (shouldSucceed) {
            if (approved != type(uint256).max) expectedAllowance[owner][spender] = approved - amount;
            _move(owner, to, amount);
        }
    }

    function _move(address from, address to, uint256 amount) private {
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function _checkResult(bool success, bytes memory result, bool shouldSucceed) private {
        require(success == shouldSucceed, "call outcome differs from ledger");
        if (shouldSucceed) {
            require(result.length == 32 && abi.decode(result, (bool)), "missing ERC20 success result");
            ++successfulCalls;
        } else {
            ++rejectedCalls;
        }
    }

    /// @dev Bias toward boundaries without discarding arbitrary uint256 inputs.
    function _edgeAmount(uint256 seed, uint256 limit) private pure returns (uint256) {
        uint256 mode = seed % 8;
        if (mode == 0) return 0;
        if (mode == 1) return 1;
        if (mode == 2) return limit;
        if (mode == 3) return limit + 1;
        if (mode == 4) return type(uint256).max;
        if (mode == 5) return type(uint256).max - 1;
        if (mode == 6) return seed % (limit + 1);
        return seed;
    }
}

contract SCATTokenLedgerInvariantTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    SCATLedgerHandler private handler;
    SCATToken private token;

    function setUp() public {
        handler = new SCATLedgerHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// @dev Checking every account and approval catches theft that preserves aggregate supply,
    /// allowance corruption, and any state change made by a rejected operation.
    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 96
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_EveryBalanceAndAllowanceMatchesIndependentLedger() public view {
        _assertLedger();
    }

    /// @dev Guarantee the handler's success/failure and boundary paths are exercised even before
    /// random exploration: unlimited spend, empty balance, self-send, revocation and zero addresses.
    function test_HandlerExercisesSuccessfulAndRejectedCalls() public {
        handler.approve(0, 3, 4); // Unlimited.
        _assertLedger();
        handler.transferFrom(0, 3, 4, 2); // Entire balance.
        _assertLedger();
        handler.transferFrom(0, 3, 4, 1); // Insufficient balance.
        _assertLedger();
        handler.transfer(4, 4, 2); // Self-send.
        _assertLedger();
        handler.transfer(4, 0, 2); // Return entire balance.
        _assertLedger();
        handler.approve(0, 3, 0); // Revoke unlimited approval.
        _assertLedger();
        handler.transferFrom(0, 3, 4, 1); // Insufficient allowance.
        _assertLedger();
        handler.transfer(0, 5, 2); // Invalid receiver.
        _assertLedger();
        handler.approve(0, 5, 2); // Invalid spender.
        _assertLedger();
        handler.approve(5, 3, 2); // Invalid approver.
        _assertLedger();
        handler.transferFrom(5, 3, 4, 0); // Invalid sender, including zero amount.
        _assertLedger();
        assertEq(handler.successfulCalls(), 5);
        assertEq(handler.rejectedCalls(), 6);
    }

    function afterInvariant() public {
        // The factory, PoolManager, distributor and holders have identical transfer rights.
        // All legitimately held tokens can be returned to the deployer after any random sequence.
        for (uint256 i = 1; i < 5; ++i) {
            handler.transfer(i, 0, 2);
            _assertLedger();
        }
        assertEq(token.balanceOf(address(handler)), SUPPLY);
    }

    function _assertLedger() private view {
        uint256 sum;
        for (uint256 i; i < 6; ++i) {
            address holder = handler.actors(i);
            require(token.balanceOf(holder) == handler.expectedBalance(holder), "holder balance differs from ledger");
            sum += token.balanceOf(holder);
            for (uint256 j; j < 6; ++j) {
                address spender = handler.actors(j);
                require(
                    token.allowance(holder, spender) == handler.expectedAllowance(holder, spender),
                    "approval differs from ledger"
                );
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
