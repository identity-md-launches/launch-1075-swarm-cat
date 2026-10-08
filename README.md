# swarm cat (SCAT)

`src/SCATToken.sol:SCATToken` is a dependency-free ERC-20 with a fixed supply of
1,000,000,000 SCAT at 18 decimals: `1000000000000000000000000000` minor units.
Its argument-free constructor mints the entire supply to `msg.sender` and emits
the mint `Transfer` event. When the launch factory deploys it, the factory holds
all tokens. The token performs no launch allocation itself.

The name, symbol, decimals and total supply are constants. There is no owner,
admin, mint or burn function, proxy, initializer, upgrade path, pause, blacklist,
fee, tax, transfer limit, external call or privileged address. The only mutable
state is balances and allowances. There are no application contracts to deploy.

## Build and test

Install Foundry and Solidity **0.8.26** in the build environment, then run:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun, optimizer enabled with 200 runs, and
`bytecode_hash = "none"`. FFI and filesystem permissions are disabled. There are
no package downloads, remappings, submodules or library dependencies. All source
and test support files are included; the installed compiler and Foundry are the
only build prerequisites. The tests need no RPC, keys or environment variables.

Tests cover constructor minting through direct deployment and CREATE2; complete,
zero, self and contract-recipient transfers; event fields; approval replacement,
revocation and isolation; finite and unlimited allowances; insufficient balances
and allowances; atomic rollback; invalid addresses; unsupported administrative
calls; and a runtime opcode scan. Three fuzz tests run 1,000 cases each. A stateful
invariant runs 256 sequences of 64 transfer/approval actions, checks supply
conservation, and checks that every holder can transfer their full balance after
each sequence. Fixture addresses appear only in tests.

## ERC-20 behavior

- Transfers move the exact requested amount and return `true`. Invalid calls
  revert with descriptive custom errors. Zero-value transfers emit `Transfer`.
- Sending to the zero address reverts, including zero-value transfers. Sending
  to a nonzero sink address does not reduce `totalSupply`.
- `approve` replaces the caller's allowance and emits `Approval`. Zero revokes
  approval. The spender must be nonzero. Holders should account for the normal
  ERC-20 approval replacement race when changing an existing allowance.
- `transferFrom` requires the caller's allowance even when caller equals holder.
  Finite allowances decrease; `type(uint256).max` remains unlimited. Spending
  does not emit an additional `Approval`; read `allowance` for its current value.
  A failed transfer also rolls back the allowance change.
- There are no recipient callbacks or recovery functions. Direct Ether payments
  and unknown function selectors revert. Tokens sent to the token contract
  itself cannot be recovered by an administrator.

## Deployment parameters

The launch manifest is `launch.json`, with `kind: "custom_token"`,
`token.contract: "SCATToken"`, `constructorArgs: []`, and `contracts: []`.
Chain selection is external to the manifest schema; no root `chainId` field is
included. These addresses and economics are supplied by the assignment.

| Parameter | Value |
| --- | --- |
| Target network | Ethereum mainnet, chain ID 1 |
| PoolManager | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Paired currency (IMD) | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee | `3000` (0.3% pool fee; SCAT has no transfer fee) |
| Tick spacing | `60` |
| Provenance initialPrice | `125270724187523965593206900` |
| economics.poolBps | `9000` of the entire token supply |
| economics.initialMarketCapWei | `2500000000000000000000` paired-currency minor units (2500 IMD) |
| economics.remainderTo | `0x000000000000000000000000000000000000dead` |

`pool.initialPrice` records the requested sqrtPriceX96 provenance with SCAT as
currency0 and the paired currency as currency1. It is not a raw token price or
an instruction to ignore the deployed address order. The external launch
deployer derives the actual opening price from the economics and sorts the
deployed currencies. The token neither reads nor enforces pool parameters.

## Launch responsibilities and assumptions

1. The network's launcher selects mainnet and deploys the compiled `SCATToken`
   creation bytecode through `ProjectFactory.launchCustom`, with no constructor
   arguments. A helper deployment contract would receive the supply itself, so
   the factory must be the immediate creator. Verify its initial balance and
   `totalSupply` are both exactly `1e27` minor units.
2. The external factory sends 10% (100,000,000 SCAT) through its Merkle
   distributor. Neither the token nor any delivered application contract
   calculates or sends that allocation. The factory/distributor own contributor
   accounting and claim authorization.
3. The factory uses the 90% pool budget (900,000,000 SCAT) to seed Uniswap v4 via
   the supplied PoolManager. It derives the opening price, ticks and liquidity
   and handles pool initialization and settlement. All actual seed transfers
   arrive without deductions. Any residual amount, including liquidity-rounding
   dust, goes to the exact requested `remainderTo`. The nominal allocation has
   no unallocated share. A transfer to that address leaves the supply unchanged.
4. Before launch, the operator checks the network, factory configuration, paired
   currency and PoolManager deployments, reviews the derived pool parameters,
   and runs the platform's protected launch checks. After deployment the
   operator verifies the source/bytecode and resulting allocations. The token
   requires no settings or maintenance after launch.

The local launch-flow test models the ERC-20 settlement legs: factory to
distributor and PoolManager, distributor to claimant, PoolManager to trader and
trader back to PoolManager. It does **not** implement Merkle proofs, Uniswap
liquidity math, or real swaps. The supplied protected harness tests actual v4
seeding and swaps in the platform environment; it imports platform components
and requires launch-specific inputs that are not part of this repository.
Live mainnet integration and deployment address verification remain the launch
operator's responsibility. No transactions are broadcast by this project.

The contract has been reviewed locally for supply conservation, self-transfer
accounting, allowance authorization/rollback, privileged entry points and
external-call surfaces. Foundry tests and opcode checks are not an independent
security audit. Slither, Mythril and live fork tests are not included in the local
validation; independent adversarial review belongs to the release process.
