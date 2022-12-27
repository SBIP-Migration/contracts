// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.1;

/**
 * @title IDebtToken
 * @notice Defines the interface for the debt token
 * @author Matthew
 **/

interface IDebtToken {
  /**
   * @dev Returns the underlying asset of the debt token.
   */
  function UNDERLYING_ASSET_ADDRESS() external view returns (address);

  /**
   * @dev Returns the address of the associated LendingPool for the debt token.
   */
  function POOL() external view returns (address);

  /**
   * @dev Sets the amount of allowance for delegatee to borrow of a particular debt token.
   */
  function approveDelegation(address delegatee, uint256 amount) external;

  /**
   * @dev Returns the borrow allowance toUser has been given by fromUser for particular debt token
   */
  function borrowAllowance(address fromUser, address toUser) external returns (uint256);
}