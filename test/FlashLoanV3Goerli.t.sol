// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.1;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "src/FlashLoanV3.sol";

import "forge-std/console.sol";

import {DataTypes} from "src/libraries/DataTypes.sol";
import {IDebtToken} from "src/interfaces/IDebtToken.sol";
import {IPoolDataProvider} from "src/interfaces/IPoolDataProviderV3.sol";

// Goerli chain, with real wallet data
contract FlashLoanV3Goerli is Test {
  FlashLoanV3 flashloan;

  address private constant AAVE_LENDING_POOL_ADDRESS_PROVIDER =
    0xc4dCB5126a3AfEd129BC3668Ea19285A9f56D15D;
  address private constant AAVE_PROTOCOL_DATA_PROVIDER =
    0x9BE876c6DC42215B00d7efe892E2691C3bc35d10;

  // Borrowed
  address private constant USDC_ADDRESS =
    0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;
  address private constant A_USDC_ADDRESS =
    0x1Ee669290939f8a8864497Af3BC83728715265FF;
  address private constant STABLE_DEBT_USDC =
    0xF04958AeA8b7F24Db19772f84d7c2aC801D9Cf8b;
  address private constant VARIABLE_DEBT_USDC =
    0x3e491EB1A98cD42F9BBa388076Fd7a74B3470CA0;

  address private constant WETH_ADDRESS =
    0x2e3A2fb8473316A02b8A297B982498E661E1f6f5;
  address private constant A_WETH_ADDRESS =
    0x27B4692C93959048833f40702b22FE3578E77759;
  address private constant VARIABLE_DEBT_WETH =
    0x2b848bA14583fA79519Ee71E7038D0d1061cd0F1;
  address private constant STABLE_DEBT_WETH =
    0xAc4d51461a46E359FBDE603f4183dffFd6Ff562B;

  // No positions on Aave yet
  address private constant RECEIVER =
    0xf20Fc5343AA0257eCff5e4BB78F127312f899692;
  address private migrateAavePositionsAddress;

  IPoolDataProvider poolDataProvider =
    IPoolDataProvider(AAVE_PROTOCOL_DATA_PROVIDER);

  function setUp() public {
    flashloan = new FlashLoanV3(AAVE_LENDING_POOL_ADDRESS_PROVIDER);
    migrateAavePositionsAddress = flashloan.getContractAddress();
    vm.label(RECEIVER, "Receiver");
  }

  function test_migrateUSDCPositionWithWETHCollateral() public {
    address BORROWER = 0x68929570Ee8a4Da4Fc7634340D0d92585B2Aa313;
    vm.label(BORROWER, "Borrower");

    vm.startPrank(BORROWER);

    DataTypes.DebtTokenPosition[]
      memory debtTokenPositions = new DataTypes.DebtTokenPosition[](1);
    DataTypes.aTokenPosition[]
      memory aTokenPositions = new DataTypes.aTokenPosition[](1);

    // Initial Borrower balances
    (, , uint256 initialUSDCBorrowerVariableDebt, , , , , , ) = poolDataProvider
      .getUserReserveData(USDC_ADDRESS, BORROWER);

    (uint256 initialWETHBorrowerATokenBalance, , , , , , , , ) = poolDataProvider.getUserReserveData(
      WETH_ADDRESS,
      BORROWER
    );
    
    // Initial Receiver balances
    (uint256 initialWETHReceiverATokenBalance, , , , , , , , ) = poolDataProvider
      .getUserReserveData(WETH_ADDRESS, RECEIVER);

    (, , uint256 initialUSDCReceiverVariableDebt, , , , , , ) = poolDataProvider
      .getUserReserveData(USDC_ADDRESS, RECEIVER);

    // USDC debt
    debtTokenPositions[0] = DataTypes.DebtTokenPosition({
      stableDebtAmount: 0,
      variableDebtAmount: initialUSDCBorrowerVariableDebt,
      tokenAddress: USDC_ADDRESS
    });

    // WETH collateral
    aTokenPositions[0] = DataTypes.aTokenPosition({
      tokenAddress: WETH_ADDRESS,
      aTokenAddress: A_WETH_ADDRESS,
      amount: initialWETHBorrowerATokenBalance
    });

    // Pre-approve aToken positions transfer on "sender" wallet
    IERC20(A_WETH_ADDRESS).approve(
      migrateAavePositionsAddress,
      type(uint256).max
    );
    vm.stopPrank();

    vm.startPrank(RECEIVER);

    // Pre-approve borrow positions on "RECEIVER" wallet
    IDebtToken(VARIABLE_DEBT_USDC).approveDelegation(
      migrateAavePositionsAddress,
      type(uint256).max
    );
    vm.stopPrank();

    vm.startPrank(BORROWER);

    flashloan.migrateAavePositions(
      RECEIVER,
      debtTokenPositions,
      aTokenPositions
    );

    // Final "Borrower" balances
    (, , uint256 usdcBorrowerVariableDebt, , , , , , ) = poolDataProvider
      .getUserReserveData(USDC_ADDRESS, BORROWER);
    (uint256 wethBorrowerATokenBalance, , , , , , , , ) = poolDataProvider
      .getUserReserveData(WETH_ADDRESS, BORROWER);

    // Final "Receiver" balances
    (, , uint256 usdcReceiverVariableDebt, , , , , , ) = poolDataProvider
      .getUserReserveData(USDC_ADDRESS, RECEIVER);
    (uint256 wethReceiverATokenBalance, , , , , , , , ) = poolDataProvider
      .getUserReserveData(WETH_ADDRESS, RECEIVER);

    // Lending positions transferred to RECEIVER account
    assertEq(initialWETHBorrowerATokenBalance - wethBorrowerATokenBalance, wethReceiverATokenBalance - initialWETHReceiverATokenBalance);

    // On Goerli V3 -> 0.05% = 5 / 10000
    uint256 flashloanFeeUsdc = (initialUSDCBorrowerVariableDebt * 5) / 10000;
    assertEq(usdcReceiverVariableDebt - initialUSDCReceiverVariableDebt, initialUSDCBorrowerVariableDebt + flashloanFeeUsdc);
  }
}
