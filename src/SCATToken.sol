// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title swarm cat
/// @notice Fixed-supply ERC-20. The constructor gives the entire supply to its caller.
/// @dev Launch distribution belongs to the external factory. There are no privileged roles,
/// mint/burn entry points, transfer hooks, fees, limits, or external calls.
contract SCATToken {
    string public constant name = "swarm cat";
    string public constant symbol = "SCAT";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address holder => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    /// @notice Move an exact amount of SCAT, including zero, to a nonzero recipient.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Replace the caller's allowance for spender. Zero revokes it.
    /// @dev A maximum uint256 allowance is unlimited and is not reduced by transferFrom.
    function approve(address spender, uint256 value) external returns (bool) {
        if (msg.sender == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Move tokens using an allowance granted to the caller by from.
    /// @dev Finite allowances decrease without an additional Approval event. A failed transfer
    /// reverts the entire operation, including any allowance change.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 available = allowance[from][msg.sender];
        if (available != type(uint256).max) {
            if (available < value) revert ERC20InsufficientAllowance(msg.sender, available, value);
            allowance[from][msg.sender] = available - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));

        uint256 available = balanceOf[from];
        if (available < value) revert ERC20InsufficientBalance(from, available, value);

        balanceOf[from] = available - value;
        // Read after the debit so a self-transfer preserves the balance.
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
