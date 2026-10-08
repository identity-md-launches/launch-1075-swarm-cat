// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the Foundry cheatcodes used by this dependency-free suite.
interface Vm {
    function prank(address sender) external;
    function expectRevert(bytes calldata reason) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function deal(address account, uint256 balance) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "unexpected integer");
    }

    function assertEq(string memory actual, string memory expected) internal pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), "unexpected string");
    }

    function assertTrue(bool value) internal pure {
        require(value, "expected true");
    }
}
