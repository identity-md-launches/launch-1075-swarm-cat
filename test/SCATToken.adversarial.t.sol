// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SCATToken} from "../src/SCATToken.sol";
import {TestBase} from "./TestBase.sol";

contract SCATTokenAdversarialTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    SCATToken private token;

    function setUp() public {
        token = new SCATToken();
    }

    /// @dev Exercise holder/spender/recipient aliases, including all three being identical.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DelegatedTransferWithAliasedRoles(
        uint256 approvalSeed,
        uint256 amountSeed,
        uint8 layout,
        bool unlimited
    ) public {
        address holder = address(this);
        address spender = layout % 2 == 0 ? SPENDER : holder;
        address recipient = layout % 3 == 0 ? holder : (layout % 3 == 1 ? spender : BOB);
        uint256 approved = unlimited ? type(uint256).max : approvalSeed % (SUPPLY + 1);
        uint256 limit = approved < SUPPLY ? approved : SUPPLY;
        uint256 amount = amountSeed % (limit + 1);

        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));

        assertEq(token.balanceOf(holder), recipient == holder ? SUPPLY : SUPPLY - amount);
        if (recipient != holder) assertEq(token.balanceOf(recipient), amount);
        assertEq(token.allowance(holder, spender), unlimited ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev A failure after a successful spend must preserve that spend and the remaining approval.
    /// Includes approvals larger than the supply, MAX-1 and the unlimited sentinel.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_FailedDelegatedTransferIsAtomicAfterPriorSpend(
        uint256 heldSeed,
        uint256 spentSeed,
        uint256 approvalSeed,
        bool unlimited,
        bool invalidRecipient
    ) public {
        uint256 held = heldSeed % (SUPPLY + 1);
        uint256 spent = spentSeed % (held + 1);
        uint256 approved = unlimited ? type(uint256).max : held + 1 + approvalSeed % (type(uint256).max - held - 1);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, spent));

        uint256 balance = held - spent;
        uint256 remainingApproval = unlimited ? approved : approved - spent;
        bytes memory expectedError = invalidRecipient
            ? abi.encodeWithSelector(SCATToken.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(SCATToken.ERC20InsufficientBalance.selector, ALICE, balance, balance + 1);
        vm.expectRevert(expectedError);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, invalidRecipient ? address(0) : BOB, invalidRecipient ? balance : balance + 1);

        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(ALICE, SPENDER), remainingApproval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ReplacementApprovalDoesNotAddToUnusedBudget(uint256 oldSeed, uint256 newSeed, uint256 spentSeed)
        public
    {
        uint256 oldApproval = oldSeed % (SUPPLY / 4 + 1);
        uint256 newApproval = newSeed % (SUPPLY / 4 + 1);
        uint256 spent = spentSeed % (oldApproval + 1);
        token.approve(SPENDER, oldApproval);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        token.approve(SPENDER, newApproval);

        vm.expectRevert(
            abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, SPENDER, newApproval, newApproval + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, newApproval + 1);
        assertEq(token.allowance(address(this), SPENDER), newApproval);
        assertEq(token.balanceOf(BOB), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, newApproval));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(BOB), newApproval);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent - newApproval);

        token.approve(SPENDER, type(uint256).max);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), newApproval);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ApprovalBelongsToHolderAndDoesNotFollowTokens(uint256 amountSeed) public {
        uint256 amount = 1 + amountSeed % SUPPLY;
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));

        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.allowance(ALICE, SPENDER), 0);

        // The original approval still applies when the original holder receives tokens back.
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), amount));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY));
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
    }

    function test_MaxMinusOneApprovalIsFiniteEvenWhenBalanceReturns() public {
        uint256 approved = type(uint256).max - 1;
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), approved - 2 * SUPPLY);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Correct ABI argument types ensure rejection is not just an invalid bool decoding error.
    function test_CanonicalAdminCalldataCannotFreezeOrSeizeApprovedHoldings() public {
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        token.approve(address(this), 100);
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true);
        calls[1] = abi.encodeWithSignature("setBlocked(address,bool)", ALICE, true);
        calls[2] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[3] = abi.encodeWithSignature("freezeAccount(address)", ALICE);
        calls[4] = abi.encodeWithSignature("blocklist(address)", ALICE);
        calls[5] = abi.encodeWithSignature("lock(address)", ALICE);
        calls[6] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 100);
        calls[7] = abi.encodeWithSignature("mint(address,uint256)", ALICE, 1);
        calls[8] = abi.encodeWithSignature("pause()");
        calls[9] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[10] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[11] = abi.encodeWithSignature("initialize(address)", BOB);
        address[3] memory callers = [address(this), ALICE, BOB];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool success,) = address(token).call(calls[j]);
                require(!success, "unexpected privileged entry point");
            }
        }
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.allowance(ALICE, address(this)), 100);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }
}
