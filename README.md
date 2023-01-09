# <h1 align="center"> Aave Migration Tool </h1>

**Migrate your lending & borrowing positions on Aave to another wallet**


## Motivation
The risk of hacks in the crypto space is pretty high, especially to users who are active in the space, who use various DeFi protocols such as Aave.

When a user's wallet gets hacked, depending on the hacker, they may have a very brief period of time to migrate their funds to their new wallet.

This tool is meant to make that flow much smoother and simpler, with a click of a button, users can migrate their entire positions on Aave (including debts) without having the funds to repay their debt at that moment.
## What is this?
This is a tool to help users who lend / borrow on Aave, to migrate their positions in their current wallet to another wallet that they own.

The smart contract uses Aave flashloan to help out transfer their positions by injecting external liquidity.
## Deployments

Deployed on Goerli 
- Aave V3: https://goerli.etherscan.io/address/0x5b5c27bda785970d5207fb5a9ed0dcdd19bd018e
- Aave V2: https://goerli.etherscan.io/address/0xb139b3508d637cce06a160666348ebaf24b77fd7#code

Website Demo: https://client-five-psi.vercel.app/

## How does it work?

It is a 5 step process:
1. Take flashloan from Aave Lending Pool
2. Use flashloan funds to **repay** all existing debts in original wallet
3. Transfer lending positions (aTokens) from the original wallet to destination wallet
4. Reborrow previous debt positions in destination wallet
5. Repay flashloan with an additional flashloan fee

## Fees
The cost incurred for the users to migrate their positions are as follows:
- `approve` each of the lending positions to the contract
- `approveDelegation` each of the previous debts in the "original" wallet, to allow the contract to borrow on behalf of the "destination" wallet
- Transaction cost for the smart contract call to migrate their positions
- Flash loan fee that is determined by Aave DAO when we borrowed the flash loan
