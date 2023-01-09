# <h1 align="center"> Aave Migration Tool </h1>

**Migrate your lending & borrowing positions on Aave to another wallet**

## Motivation

**1) Bad user experience when doing asset migration manually from 1 wallet address to another**

Numerous Steps required to execute manual transfer:

i) Debt from sender wallet needs to be payed back in order for deposited collateral to be retrieved

<img width="635" alt="Screenshot 2023-01-09 at 9 22 40 PM" src="https://user-images.githubusercontent.com/14165832/211318046-e0ea331a-1cd2-4b02-8bc7-22557b895ed3.png">

ii) Deposited collateral needs to be retrieved

<img width="639" alt="Screenshot 2023-01-09 at 9 22 33 PM" src="https://user-images.githubusercontent.com/14165832/211318293-bf89578c-7384-4c73-a9ac-a9cc5b2aa149.png">

iii) Sometimes users will borrow from recipient wallet first to pay back Step (1). Users risk liquidation if price moves drastically against them during the manual transfer process.

<img width="211" alt="Screenshot 2023-01-09 at 9 29 32 PM" src="https://user-images.githubusercontent.com/14165832/211319386-ba197a82-4495-4d11-bb88-5fcbe1799e2e.png">

**2) A more serious problem when mitigating a hack (Time sensitive)**

Assuming a user's wallet gets hacked, the user will be competing against the hacker and only has a very brief period of time to migrate their funds to their new wallet. Speed of asset transfer is critical to saving victim's funds.

## What is this?
This tool is meant to make the transfer of lending and borrowed assets much smoother,simpler and faster from their current wallet to another wallet that they own.
With a click of a button, users can migrate their entire positions on Aave (including debts) without having the funds to repay their debt at that moment.

The smart contract uses Aave flashloan to help out transfer their positions by injecting external liquidity.

<img width="597" alt="Screenshot 2023-01-09 at 9 47 40 PM" src="https://user-images.githubusercontent.com/14165832/211322848-4784c737-6e67-4245-b641-f5b490e7ac85.png">


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

## Stretch Goals
1) We could propose this tool for AAVE to enhance user experience. Allow this function for users to send to their whitelisted addresses only ( Mitigate hacks and increase user satisfaction)
2) To offer these services to other lending and borrowing protocols like Compound 
