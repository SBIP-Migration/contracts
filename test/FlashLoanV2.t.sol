// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.1;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "src/FlashLoanV2.sol";

import { DataTypes } from "src/libraries/DataTypes.sol";
import { IDebtToken } from "src/interfaces/IDebtToken.sol";


contract FlashLoanV2Test is Test {
    FlashLoanV2 flashloan;

    address private constant AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address private constant AAVE_LENDING_POOL_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5; 
    
    // Borrowed
    address private constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant STABLE_DEBT_USDC = 0xE4922afAB0BbaDd8ab2a88E0C79d884Ad337fcA6;
    address private constant VARIABLE_DEBT_USDC = 0x619beb58998eD2278e08620f97007e1116D5D25b;

    // Collateral
    address private constant A_DAI_ADDRESS = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    // Collateral (underlying)
    address private constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    
    // https://etherscan.io/tx/0xb631bbbfa79b3f09eaa32a2e72e13c78aaac9880798bb50137baef7057d98b4c
    address private constant BORROWER = 0xb6aF7C04f67B5eb61F0DC7aC4a760888EC3E3887;

    // No positions on Aave yet
    address private constant RECEIVER = 0x716Abf4d1e0FE3335629C43adA2680Da5BeE67be;

    IERC20 usdcToken = IERC20(USDC_ADDRESS);
    IERC20 daiToken = IERC20(DAI_ADDRESS);
    IERC20 aDaiToken = IERC20(A_DAI_ADDRESS);

    function setUp() public {
        flashloan = new FlashLoanV2(AAVE_LENDING_POOL_PROVIDER);
        vm.label(BORROWER, "Borrower");
        vm.label(RECEIVER, "Receiver");
    }

    function test_migrateUSDCPosition() public {
        vm.startPrank(BORROWER); 
        DataTypes.DebtTokenPosition[] memory debtTokenPositions = new DataTypes.DebtTokenPosition[](1);
        DataTypes.aTokenPosition[] memory aTokenPositions = new DataTypes.aTokenPosition[](1);

        emit log_named_uint("USDC Balance before", usdcToken.balanceOf(BORROWER));
        emit log_named_uint("DAI Balance before", daiToken.balanceOf(BORROWER));
        emit log_named_uint("ADAI Balance before", aDaiToken.balanceOf(BORROWER));

        debtTokenPositions[0] = DataTypes.DebtTokenPosition({
            stableDebtAmount: 0, 
            variableDebtAmount: usdcToken.balanceOf(BORROWER), 
            tokenAddress: USDC_ADDRESS
        });
        
        aTokenPositions[0] = DataTypes.aTokenPosition({
            tokenAddress: DAI_ADDRESS,
            aTokenAddress: A_DAI_ADDRESS,
            amount: aDaiToken.balanceOf(BORROWER)
        });

        // Pre-approve aToken positions transfer on "sender" wallet
        IERC20(A_DAI_ADDRESS).approve(
            flashloan.getContractAddress(), 
            aDaiToken.balanceOf(BORROWER)
        );

        vm.stopPrank();

        vm.startPrank(RECEIVER);
        // Pre-approve borrow positions on "RECEIVER" wallet
        IDebtToken(VARIABLE_DEBT_USDC).approveDelegation(flashloan.getContractAddress(), usdcToken.balanceOf(BORROWER));
        IDebtToken(STABLE_DEBT_USDC).approveDelegation(flashloan.getContractAddress(), usdcToken.balanceOf(BORROWER));
        vm.stopPrank();

        vm.startPrank(BORROWER);
        flashloan.migrateAavePositions(
            RECEIVER, 
            debtTokenPositions, 
            aTokenPositions
        );
        emit log_named_uint("USDC Balance after", usdcToken.balanceOf(BORROWER));
    }


    function testBar() public {
        assertEq(uint256(1), uint256(1), "ok");
    }

    function testFoo(uint256 x) public {
        vm.assume(x < type(uint128).max);
        assertEq(x + x, x * 2);
    }
}