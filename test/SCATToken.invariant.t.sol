// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SCATToken} from "../src/SCATToken.sol";
import {TestBase} from "./TestBase.sol";

/// @dev All recipients are drawn from this closed set so conservation can be checked exactly.
contract TokenHandler is TestBase {
    SCATToken public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA11), address(0xD157)];

    constructor(SCATToken token_) {
        token = token_;
    }

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address sender = actors[senderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        amount %= token.balanceOf(sender) + 1;
        vm.prank(sender);
        assertTrue(token.transfer(recipient, amount));
    }

    function approve(uint256 holderSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address holder = actors[holderSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = unlimited ? type(uint256).max : amount % (1_000_000_000e18 + 1);
        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 holderSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amount) external {
        address holder = actors[holderSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 approved = token.allowance(holder, spender);
        uint256 available = token.balanceOf(holder);
        uint256 limit = available < approved ? available : approved;
        amount %= limit + 1;
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.allowance(holder, spender), approved == type(uint256).max ? approved : approved - amount);
    }
}

contract SCATTokenInvariantTest is TestBase {
    SCATToken internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new SCATToken();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), 1_000_000_000e18);
    }

    /// @dev Foundry's invariant runner uses this interface without requiring forge-std.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_AllBalancesSumToFixedSupply() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, 1_000_000_000e18);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// @dev After each sequence every holder can still transfer their entire balance.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            uint256 held = token.balanceOf(holder);
            vm.prank(holder);
            assertTrue(token.transfer(address(this), held));
            assertEq(token.balanceOf(holder), 0);
        }
        assertEq(token.balanceOf(address(this)), 1_000_000_000e18);
        assertEq(token.totalSupply(), 1_000_000_000e18);
    }
}
