// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SCATToken} from "../src/SCATToken.sol";
import {TestBase} from "./TestBase.sol";

/// @dev A local deployment fixture, never a launch application contract.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (SCATToken) {
        return new SCATToken{salt: salt}();
    }
}

contract RejectingRecipient {
    fallback() external {
        revert("no callbacks accepted");
    }
}

contract SCATTokenTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant REMAINDER_TO = 0x000000000000000000000000000000000000dEaD;

    SCATToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SCATToken();
    }

    function test_ConstructorMintsEntireSupplyAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        SCATToken fresh = new SCATToken();
        assertEq(fresh.name(), "swarm cat");
        assertEq(fresh.symbol(), "SCAT");
        assertEq(fresh.decimals(), 18);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
        assertEq(fresh.balanceOf(address(fresh)), 0);
        assertEq(fresh.balanceOf(address(0)), 0);
    }

    function test_Create2MintsToFactoryRatherThanTransactionOrigin() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(ALICE);
        SCATToken launched = factory.deploy(keccak256("SCAT launch fixture"));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(ALICE), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMoveAndReturnWithoutLimits() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_TransferEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 123e18);
        assertTrue(token.transfer(ALICE, 123e18));
        assertEq(token.balanceOf(ALICE), 123e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123e18);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(SCATToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
    }

    function test_MaximumTransferCannotOverflowOrChangeSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SCATToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ZeroRecipientAlwaysReverts(uint256 amount) public {
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_ApproveReplacesAndRevokesOnlyCallersAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertTrue(token.approve(SPENDER, 40));
        assertEq(token.allowance(address(this), SPENDER), 40);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 999));
        assertEq(token.allowance(address(this), SPENDER), 40);
        assertEq(token.allowance(ALICE, SPENDER), 999);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_ApproveZeroApproverReverts() public {
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 1);
    }

    function test_FiniteAllowanceCanBeSpentExactlyOnce() public {
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 40));
        assertEq(token.allowance(address(this), SPENDER), 60);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), BOB, 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 60));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 40);
        assertEq(token.balanceOf(BOB), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_InfiniteAllowanceRemainsInfiniteAcrossSpends() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 7));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 7));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
    }

    function test_InsufficientBalanceRollsBackAllowance() public {
        token.approve(SPENDER, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(SCATToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, SUPPLY + 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_InvalidRecipientRollsBackAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroSenderCannotTransferEvenZero() public {
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
    }

    function test_TransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(SPENDER, SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_TransferFromByHolderStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
    }

    function test_ZeroTransferFromWithoutAllowanceSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_ApprovalDoesNotAuthorizeAnotherSpender() public {
        token.approve(SPENDER, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_NoRecipientCallbackIsRequired() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 100));
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(recipient), 100));
        assertEq(token.balanceOf(address(recipient)), 200);
    }

    function test_TransferToRemainderAddressDoesNotBurnSupply() public {
        assertTrue(token.transfer(REMAINDER_TO, SUPPLY));
        assertEq(token.balanceOf(REMAINDER_TO), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Exercises token settlement legs only. It does not emulate Uniswap price/liquidity math.
    function test_FactoryDistributionClaimsAndPoolManagerTransfersAreExact() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        SCATToken launched = factory.deploy(keccak256("distribution fixture"));
        uint256 swarm = SUPPLY / 10;
        uint256 poolBudget = SUPPLY * 9000 / 10_000;
        // Model one minor unit of liquidity-rounding dust forwarded by the external factory.
        uint256 seeded = poolBudget - 1;
        assertEq(launched.balanceOf(address(factory)), SUPPLY);

        vm.prank(address(factory));
        assertTrue(launched.transfer(DISTRIBUTOR, swarm));
        vm.prank(address(factory));
        assertTrue(launched.transfer(POOL_MANAGER, seeded));
        vm.prank(address(factory));
        assertTrue(launched.transfer(REMAINDER_TO, 1));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(DISTRIBUTOR), swarm);
        assertEq(launched.balanceOf(POOL_MANAGER), seeded);
        assertEq(launched.balanceOf(REMAINDER_TO), 1);

        vm.prank(DISTRIBUTOR);
        assertTrue(launched.transfer(ALICE, swarm));
        assertEq(launched.balanceOf(ALICE), swarm);
        assertEq(launched.balanceOf(DISTRIBUTOR), 0);

        uint256 bought = 1_234e18;
        vm.prank(POOL_MANAGER);
        assertTrue(launched.transfer(BOB, bought));
        assertEq(launched.balanceOf(BOB), bought);
        assertEq(launched.balanceOf(POOL_MANAGER), seeded - bought);
        vm.prank(BOB);
        assertTrue(launched.transfer(POOL_MANAGER, bought));
        assertEq(launched.balanceOf(BOB), 0);
        assertEq(launched.balanceOf(POOL_MANAGER), seeded);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_NoAdminMintBurnOrUpgradeEntryPointsForDeployerOrStranger() public {
        token.transfer(ALICE, 100);
        string[24] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "setMinter(address)",
            "initialize(address)",
            "upgradeTo(address)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "setFee(uint256)",
            "setTax(uint256)",
            "setMaxTxAmount(uint256)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "setBlacklist(address,bool)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, 100);
            (bool deployerSucceeded,) = address(token).call(data);
            require(!deployerSucceeded, signatures[i]);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(data);
            require(!strangerSucceeded, signatures[i]);
        }
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_UnknownCallAndEtherAreRejected() public {
        (bool unknownSucceeded,) = address(token).call(hex"deadbeef");
        assertTrue(!unknownSucceeded);
        vm.deal(address(this), 1 ether);
        (bool etherSucceeded,) = address(token).call{value: 1 ether}("");
        assertTrue(!etherSucceeded);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory code = address(token).code;
        assertTrue(code.length > 0 && code.length <= 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            require(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferRoundTripConservesSupply(address recipient, uint256 amount) public {
        if (recipient == address(0) || recipient == address(this)) recipient = ALICE;
        amount %= SUPPLY + 1;
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(recipient);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AllowanceLimitsSpendingAndIsAtomic(uint256 approved, uint256 spent) public {
        approved %= SUPPLY + 1;
        spent %= approved + 1;
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        uint256 left = approved - spent;
        assertEq(token.allowance(address(this), SPENDER), left);
        vm.expectRevert(abi.encodeWithSelector(SCATToken.ERC20InsufficientAllowance.selector, SPENDER, left, left + 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, left + 1);
        assertEq(token.allowance(address(this), SPENDER), left);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
