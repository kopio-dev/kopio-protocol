# the kopio protocol

This repository contains the code for the kopio protocol. The protocol supports creating and managing crypto-backed synthetic assets. Prices for synthetic assets are derived from combination of oracle providers (on-demand/push).

Protocol uses the [EIP-2535](https://eips.ethereum.org/EIPS/eip-2535) architecture. It enables composability through flexibile storage patterns while allowing users to access all core functionality with a single contract address.

This readme is a usage/integration guide that assumes understanding of Solidity (especially EIP-2535), Foundry, Hardhat and [core concepts](https://kopio.gitbook.io/kopio-docs/) of kopio.

![hardhat & foundry tests](https://github.com/kopio-dev/kopio-protocol/actions/workflows/hardhat-and-foundry.yml/badge.svg?branch=main)

# Usage

A [justfile](https://github.com/casey/just) exists for running things.

### Using just commands

just installed: `just <command>`.

just not installed: `npx just <command>`.

# Setup

## Quick Setup

Install missing tools (bun, foundry, pm2), forge dependencies and run dry deploy

```sh
just setup
```

Only tools & deps can be installed with

```sh
just deps
```

## Manual Setup

Create .env file from example

```sh
cp .env.example .env
```

### Tools

#### bun

```sh
curl -fsSL https://bun.sh/install | bash
```

PM2 is required for anvil & forge development network

```sh
bun a -g pm2
```

#### Foundry

Install foundry:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

and

```sh
foundryup
```

### Dependencies

Install forge dependencies

```sh
forge install
```

Install node dependencies

```sh
bun install --yarn
```

### Compiling

#### Foundry

Compile the contracts

```sh
forge build
```

Check your setup by running the forge deployment script

```sh
bun f:dry
```

or

```sh
just d
```

#### Hardhat

Compile the contracts

```sh
bunx hardhat compile
```

Check your setup by running the hardhat deployment script

```sh
bun hh:dry
```

### Testing

**NOTE:** Primary test coverage uses hardhat. Forge tests are a work in progress

#### Hardhat

Run tests with against a local deployment fixture

```sh
bun hh:test
```

#### Foundry

```sh
forge test
```

### Deployment

#### Hardhat

Spins up hardhat node and runs deployment

```sh
bun hh:dev
```

#### Foundry

(requires PM2: `bun a -g pm2`)

Spins up anvil and runs deployment

```sh
just l
```

Observe deployment script logs

```sh
pm2 logs 1
```

Restart the network

```sh
just r
```

Stop the network

```sh
just k
```

## VSCode extensions

- Patterns in this repository have broken lsp support with these extensions: [hardhat](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity), [solidity](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity).

- Recommendation is to rather use this fork: [vsc-solidity](https://marketplace.visualstudio.com/items?itemName=0xp.vsc-solidity).

## About [ERC-2535](https://eips.ethereum.org/EIPS/eip-2535) (Diamonds) and things

### General

- External functionality lives in Facets, Use IKopio.sol or the artifact generated using `hardhat-diamond-abi` for aggregate ABI.

- Logic (mostly) lives inside internal library functions. These libraries are then attached globally to structs for convenience.

- Storage is accessed with inline assembly slot pointer assignment. To access the storage (+ attached library functions) simply call these storage getter functions anywhere.

- Vault, Factory and KopioAsset contracts do not live inside the diamond scope.

### State

#### Nay

- Do not add new state variables to the beginning or middle of structs. Doing this makes the new state variable overwrite existing state variable data and all state variables after the new state variable reference the wrong storage location.

- Do not put structs directly in structs unless you don’t plan on ever adding more state variables to the inner structs. You won't be able to add new state variables to inner structs in upgrades. This makes sense because a struct uses a fixed number of storage locations. Adding a new state variable to an inner struct would cause the next state variable after the inner struct to be overwritten. Structs that are in mappings can be extended in upgrades, because those structs are stored in random locations based on keccak256 hashing.

- Do not add new state variables to structs that are used in arrays.

- Do not use the same namespace string for different structs. This is obvious. Two different structs at the same location will overwrite each other.

#### Yay

- To add new state variables to the DiamondStorage pattern (eg. ICDPState or ms), add them to the end of the struct so it is not possible for existing functions to overwrite state variables at new storage locations.

- Above also applies to structs inside mappings.

- State variable names can be changed - but it might be confusing if different facets use different names for the same storage.

_Learning references_

_https://eip2535diamonds.substack.com/p/compliance-with-eip-2535-diamonds_

_https://github.com/solidstate-network/solidstate-solidity_

_https://eip2535diamonds.substack.com/p/how-eip2535-diamonds-reduces-gas_

### Contributions

Contributions to the kopio protocol are encouraged, feel free to open an issue or pull request. <br/> All contributions are licensed under BUSL-1.1.

### Contact

Critical bug disclosures and inquiries should be directed to: <br> ![contact_2](https://user-images.githubusercontent.com/15370712/167093578-d6c0acd8-f32c-4ca3-b22e-76c2eef7f0e3.png)
