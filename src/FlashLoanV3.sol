// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.1;

import "./aave/FlashLoanReceiverBaseV3.sol";
import "./interfaces/IPoolV3.sol";
import "./interfaces/IPoolAddressesProviderV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DataTypes} from "./libraries/DataTypes.sol";
import {IDebtToken} from "./interfaces/IDebtToken.sol";

contract FlashLoanV3 is FlashLoanReceiverBaseV3, Withdrawable, ReentrancyGuard {
  constructor(address _addressProvider)
    FlashLoanReceiverBaseV3(IPoolAddressesProvider(_addressProvider))
  {}

  function getContractAddress() public view returns (address) {
    return address(this);
  }

  /*
   * Transfer lending positions (ERC20 aToken) to recipient
   */
  function transferLendingPositions(
    DataTypes.aTokenPosition[] memory aTokenPositions,
    address sender,
    address recipient
  ) internal {
    require(
      msg.sender == address(POOL),
      "Only Aave Pool can call this function"
    );
    for (uint256 i = 0; i < aTokenPositions.length; i++) {
      bool success = IERC20(aTokenPositions[i].aTokenAddress).transferFrom(
        sender,
        recipient,
        aTokenPositions[i].amount
      );
      require(success, "Transfer of aToken failed");
    }
  }

  function repayDebtPositions(
    DataTypes.DebtTokenPosition[] memory debtTokenPositions,
    address debtor
  ) internal {
    for (uint256 i = 0; i < debtTokenPositions.length; i++) {
      DataTypes.DebtTokenPosition memory debtPosition = debtTokenPositions[i];
      if (debtPosition.stableDebtAmount != 0) {
        IERC20(debtPosition.tokenAddress).approve(
          address(POOL),
          debtPosition.stableDebtAmount
        );
        POOL.repay(
          debtPosition.tokenAddress,
          debtPosition.stableDebtAmount,
          // Stable Debt = 1
          1,
          debtor
        );
      }

      if (debtPosition.variableDebtAmount != 0) {
        IERC20(debtPosition.tokenAddress).approve(
          address(POOL),
          debtPosition.variableDebtAmount
        );
        POOL.repay(
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
    DataTypes.DebtTokenPosition[] memory debtTokenPositions,
    uint256[] memory premiums,
    address recipient
  ) internal {
    for (uint256 i = 0; i < debtTokenPositions.length; i++) {
      DataTypes.DebtTokenPosition memory debtPosition = debtTokenPositions[i];
      uint256 flPremium = premiums[i];

      bool isPremiumIncluded = false;
      if (debtPosition.stableDebtAmount != 0) {
        POOL.borrow(
          debtPosition.tokenAddress,
          debtPosition.stableDebtAmount + flPremium,
          // Stable Debt = 1
          1,
          // Default referral code
          0,
          recipient
        );
        isPremiumIncluded = true;
      }
      if (debtPosition.variableDebtAmount != 0) {
        uint256 borrowAmount = debtPosition.variableDebtAmount;
        if (!isPremiumIncluded) {
          borrowAmount += flPremium;
        }

        POOL.borrow(
          debtPosition.tokenAddress,
          borrowAmount,
          // Variable Debt = 2
          2,
          0,
          recipient
        );
      }
    }
  }

  function approveLendingPool(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums
  ) internal {
    for (uint256 i = 0; i < assets.length; i++) {
      uint256 amountOwing = amounts[i] + premiums[i];
      IERC20(assets[i]).approve(address(POOL), amountOwing);
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
  ) external override nonReentrant returns (bool) {
    //
    // This contract now has the funds requested.
    // Your logic goes here.
    //
    require(assets.length == amounts.length && amounts.length == premiums.length, "assets, amounts & premiums need to have the same length");

    (
      address _sender,
      address _recipient,
      DataTypes.aTokenPosition[] memory _aTokenPositions,
      DataTypes.DebtTokenPosition[] memory _debtTokenPositions
    ) = abi.decode(
        params,
        (
          address,
          address,
          DataTypes.aTokenPosition[],
          DataTypes.DebtTokenPosition[]
        )
      );

    // 1. For all borrowed positions in Aave, pay debt with Lending Pool
    repayDebtPositions(_debtTokenPositions, _sender);

    // 2. Transfer lending positions to recipient
    transferLendingPositions(_aTokenPositions, _sender, _recipient);

    // 3. For all previously borrowed positions, reborrow them with new account with 0.09% premium
    reborrowDebtPositions(_debtTokenPositions, premiums, _recipient);

    // At the end of your logic above, this contract owes
    // the flashloaned amounts + premiums.
    // Therefore ensure your contract has enough to repay
    // these amounts.

    // 4. Approve the LendingPool contract allowance to *pull* the owed amount
    approveLendingPool(assets, amounts, premiums);

    return true;
  }

  function _flashloan(
    address[] memory assets,
    uint256[] memory amounts,
    bytes memory params
  ) internal {
    address receiverAddress = address(this);

    address onBehalfOf = address(this);
    uint16 referralCode = 0;

    uint256[] memory modes = new uint256[](assets.length);

    // 0 = no debt (flash), 1 = stable, 2 = variable
    for (uint256 i = 0; i < assets.length; i++) {
      modes[i] = 0;
    }

    POOL.flashLoan(
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
    DataTypes.DebtTokenPosition[] memory _debtTokenPositions,
    DataTypes.aTokenPosition[] memory _aTokenPositions
  ) external {
    require(_recipientAddress != address(0), "Invalid recipient address");
    require(
      msg.sender != _recipientAddress,
      "Cannot transfer positions to self"
    );
    require(
      _debtTokenPositions.length > 0 || _aTokenPositions.length > 0,
      "No debt OR supply positions to migrate"
    );

    uint256 numDebtTokenPositions = _debtTokenPositions.length;

    // Calculate assets
    address[] memory assets = new address[](numDebtTokenPositions);
    uint256[] memory amounts = new uint256[](numDebtTokenPositions);

    for (uint256 i = 0; i < numDebtTokenPositions; i++) {
      assets[i] = _debtTokenPositions[i].tokenAddress;
      amounts[i] =
        _debtTokenPositions[i].stableDebtAmount +
        _debtTokenPositions[i].variableDebtAmount;
    }
    bytes memory params = abi.encode(
      msg.sender,
      _recipientAddress,
      _aTokenPositions,
      _debtTokenPositions
    );

    _flashloan(assets, amounts, params);
  }
}
