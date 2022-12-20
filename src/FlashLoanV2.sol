// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.2;

import "./aave/FlashLoanReceiverBaseV2.sol";
import "./interfaces/ILendingPoolV2.sol";
import "./interfaces/ILendingPoolAddressesProviderV2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DataTypes } from "./libraries/DataTypes.sol";

contract FlashLoanV2 is FlashLoanReceiverBaseV2, Withdrawable { 
  constructor(address _addressProvider) 
    FlashLoanReceiverBaseV2(_addressProvider)
  {}

  // Representation of Aave lending position
  struct aTokenPosition {
    uint256 amount;
    address aTokenAddress;
    address tokenAddress;
  }

  // Representation of Aave debt position
  struct DebtTokenPosition {
    uint256 stableDebtAmount;
    uint256 variableDebtAmount;
    address tokenAddress;
  }

  /*
   * Transfer lending positions (ERC20 aToken) to recipient
   */
  function transferLendingPositions(
    aTokenPosition[] memory aTokenPositions,
    address recipient
  ) internal {
    for (uint i = 0; i < aTokenPositions.length; i++) {
      IERC20(aTokenPositions[i].aTokenAddress).transfer(recipient, aTokenPositions[i].amount);
    }
  }

  function repayDebtPositions(
    DebtTokenPosition[] memory debtTokenPositions,
    address debtor
  ) internal {
    for (uint i = 0; i < debtTokenPositions.length; i++) {
      DebtTokenPosition memory debtPosition = debtTokenPositions[i];
      if (debtPosition.stableDebtAmount != 0) {
        IERC20(debtPosition.tokenAddress).approve(
          address(LENDING_POOL), 
          debtPosition.stableDebtAmount 
        );
        LENDING_POOL.repay(
          debtPosition.tokenAddress, 
          debtPosition.stableDebtAmount, 
          // Stable Debt = 1
          1, 
          debtor
        );
      } 
      
      if (debtPosition.variableDebtAmount != 0) {
        IERC20(debtPosition.tokenAddress).approve(
          address(LENDING_POOL), 
          debtPosition.variableDebtAmount
        );
        LENDING_POOL.repay(
          debtPosition.tokenAddress, 
          debtPosition.variableDebtAmount, 
          // Variable Debt = 2
          2, 
          debtor
        );
      }
    }
  }

  function reborrowDebtPositions(
    DebtTokenPosition[] memory debtTokenPositions,
    uint256[] memory premiums,
    address debtor
  ) internal {
    for (uint i = 0; i < debtTokenPositions.length; i++) {
      DebtTokenPosition memory debtPosition = debtTokenPositions[i];
      uint256 flPremium = premiums[i];

      bool isPremiumIncluded = false;

      if (debtPosition.stableDebtAmount != 0) {
        IERC20(debtPosition.tokenAddress).approve(
          address(LENDING_POOL), 
          debtPosition.stableDebtAmount 
        );
        LENDING_POOL.borrow(
          debtPosition.tokenAddress, 
          debtPosition.stableDebtAmount + flPremium, 
          // Stable Debt = 1
          1,
          // Default referral code 
          0,
          debtor
        );
        isPremiumIncluded = true;
      }

      if (debtPosition.variableDebtAmount != 0) {
        IERC20(debtPosition.tokenAddress).approve(
          address(LENDING_POOL), 
          debtPosition.variableDebtAmount
        );

        uint256 borrowAmount = debtPosition.variableDebtAmount;
        if (isPremiumIncluded == false) {
          borrowAmount += flPremium;
        }

        LENDING_POOL.borrow(
          debtPosition.tokenAddress, 
          borrowAmount, 
          // Variable Debt = 2
          2, 
          0,
          debtor
        );
      } 
    }
  }


  /**
     * @dev This function must be called only be the LENDING_POOL and takes care of repaying
     * active debt positions, migrating collateral and incurring new V2 debt token debt.
     *
     * @param assets The array of flash loaned assets used to repay debts.
     * @param amounts The array of flash loaned asset amounts used to repay debts.
     * @param premiums The array of premiums incurred as additional debts.
     * @param initiator The address that initiated the flash loan, unused.
     * @param params The byte array containing, in this case, the arrays of aTokens and aTokenAmounts.
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        //
        // This contract now has the funds requested.
        // Your logic goes here.
        //

        // 1. Transfer aTokenBalances to receiver
        // 2. For all assets, pay all debt
        // 3. For all assets, reborrow them in new account (with 0.09% premiums)

        (
          address _sender, 
          address _recipient,
          aTokenPosition[] memory _aTokenPositions, 
          DebtTokenPosition[] memory _debtTokenPositions 
        ) = abi.decode(params, (address, address, aTokenPosition[],  DebtTokenPosition[]));
        
        // 1. Transfer lending positions to recipient
        transferLendingPositions(_aTokenPositions, _recipient);

        // 2. For all borrowed positions in Aave, pay debt with Lending Pool
        repayDebtPositions(_debtTokenPositions, _sender);
        
        // 3. For all previously borrowed positions, reborrow them with new account with 0.09% premium
        reborrowDebtPositions(_debtTokenPositions, premiums, _recipient);


        // At the end of your logic above, this contract owes
        // the flashloaned amounts + premiums.
        // Therefore ensure your contract has enough to repay
        // these amounts.

        // Approve the LendingPool contract allowance to *pull* the owed amount
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 amountOwing = amounts[i] + premiums[i];
            IERC20(assets[i]).approve(address(LENDING_POOL), amountOwing);
        }

        return true;
    }

     function _flashloan(address[] memory assets, uint256[] memory amounts, bytes memory params)
        internal
    {
        address receiverAddress = address(this);

        address onBehalfOf = address(this);
        uint16 referralCode = 0;

        uint256[] memory modes = new uint256[](assets.length);

        // 0 = no debt (flash), 1 = stable, 2 = variable
        for (uint256 i = 0; i < assets.length; i++) {
            modes[i] = 0;
        }

        LENDING_POOL.flashLoan(
            receiverAddress,
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
        );
    }

    /*
    * Transfers Aave positions from "msg.sender" to "recipient"
    */
    function migrateAavePositions(
      address _recipientAddress,
      DebtTokenPosition[] calldata _debtTokenPositions,
      aTokenPosition[] calldata _aTokenPositions
    ) external {
      uint256 numDebtTokenPositions = _debtTokenPositions.length;

      // Calculate assets
      address[] memory assets = new address[](numDebtTokenPositions);
      uint256[] memory amounts = new uint256[](numDebtTokenPositions);

      for (uint i = 0; i < numDebtTokenPositions; i++) {
        assets[i] = _debtTokenPositions[i].tokenAddress;
        amounts[i] = _debtTokenPositions[i].stableDebtAmount + _debtTokenPositions[i].variableDebtAmount;
      }  

      bytes memory params = abi.encode(msg.sender, _recipientAddress, _aTokenPositions, _debtTokenPositions);

      _flashloan(assets, amounts, params);
    }
}
