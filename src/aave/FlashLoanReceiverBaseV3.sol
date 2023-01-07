// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.1;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanReceiverV3} from "../interfaces/IFlashLoanReceiverV3.sol";

import {IPoolAddressesProvider} from "../interfaces/IPoolAddressesProviderV3.sol";
import {IPool} from "../interfaces/IPoolV3.sol";
import "../utils/Withdrawable.sol";

/** 
    !!!
    Never keep funds permanently on your FlashLoanReceiverBase contract as they could be 
    exposed to a 'griefing' attack, where the stored funds are used by an attacker.
    !!!
 */
abstract contract FlashLoanReceiverBaseV3 is IFlashLoanReceiverV3 {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;
  IPool public immutable override POOL;

  constructor(IPoolAddressesProvider provider) {
    ADDRESSES_PROVIDER = provider;
    POOL = IPool(provider.getPool());
  }
}
