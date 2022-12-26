// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.1;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "src/FlashLoanV2.sol";

import { DataTypes } from "src/libraries/DataTypes.sol";
import { IDebtToken } from "src/interfaces/IDebtToken.sol";
import { IProtocolDataProviderV2 } from "src/interfaces/IProtocolDataProviderV2.sol";

// BLOCK_NUMBER = 16232570 -> mainnet fork (testing)
contract FlashLoanV2Test is Test {
    FlashLoanV2 flashloan;

    address private constant AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address private constant AAVE_LENDING_POOL_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5; 
    address private constant AAVE_PROTOCOL_DATA_PROVIDER = 0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d;
    
    // Borrowed
    address private constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant STABLE_DEBT_USDC = 0xE4922afAB0BbaDd8ab2a88E0C79d884Ad337fcA6;
    address private constant VARIABLE_DEBT_USDC = 0x619beb58998eD2278e08620f97007e1116D5D25b;
    
    address private constant ST_ETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private constant A_ST_ETH_ADDRESS = 0x1982b2F5814301d4e9a8b0201555376e62F82428;

    // Collateral
    address private constant A_DAI_ADDRESS = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    // Collateral (underlying)
    address private constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    IERC20 usdcToken = IERC20(USDC_ADDRESS);
    IERC20 aDaiToken = IERC20(A_DAI_ADDRESS);
    IERC20 stEthToken = IERC20(ST_ETH_ADDRESS);
    IERC20 aStEthToken = IERC20(A_ST_ETH_ADDRESS);

    // No positions on Aave yet
    address private constant RECEIVER = 0x716Abf4d1e0FE3335629C43adA2680Da5BeE67be;
    address private migrateAavePositionsAddress;

    IProtocolDataProviderV2 protocolDataProvider = IProtocolDataProviderV2(AAVE_PROTOCOL_DATA_PROVIDER);

    function setUp() public {
        flashloan = new FlashLoanV2(AAVE_LENDING_POOL_PROVIDER);
        migrateAavePositionsAddress = flashloan.getContractAddress();
        vm.label(RECEIVER, "Receiver");
    }



    function test_migrateUsdcPositionsWithDaiCollateral() public {
        // https://etherscan.io/tx/0xb631bbbfa79b3f09eaa32a2e72e13c78aaac9880798bb50137baef7057d98b4c
        address BORROWER = 0xb6aF7C04f67B5eb61F0DC7aC4a760888EC3E3887;
        vm.label(BORROWER, "Borrower");


        vm.startPrank(BORROWER); 
        DataTypes.DebtTokenPosition[] memory debtTokenPositions = new DataTypes.DebtTokenPosition[](1);
        DataTypes.aTokenPosition[] memory aTokenPositions = new DataTypes.aTokenPosition[](1);

        // https://etherscan.io/tx/0xb631bbbfa79b3f09eaa32a2e72e13c78aaac9880798bb50137baef7057d98b4c
        uint256 USDC_BORROWED = 4000 * 10**6;
        
        // TODO: Can we transfer all of them here? If not why?
        uint256 amountUsdcToTransfer = USDC_BORROWED / 2;
        uint256 initialBorrowerDaiTokenBalance = aDaiToken.balanceOf(BORROWER);
        uint256 amountDaiToTransfer = aDaiToken.balanceOf(BORROWER) * 2 / 3;

        debtTokenPositions[0] = DataTypes.DebtTokenPosition({
            stableDebtAmount: 0, 
            variableDebtAmount: amountUsdcToTransfer, 
            tokenAddress: USDC_ADDRESS
        });
        
        aTokenPositions[0] = DataTypes.aTokenPosition({
            tokenAddress: DAI_ADDRESS,
            aTokenAddress: A_DAI_ADDRESS,
            amount: amountDaiToTransfer
        });

        // Pre-approve aToken positions transfer on "sender" wallet
        IERC20(A_DAI_ADDRESS).approve(
            migrateAavePositionsAddress, 
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(RECEIVER);
        // Pre-approve borrow positions on "RECEIVER" wallet
        IDebtToken(VARIABLE_DEBT_USDC).approveDelegation(migrateAavePositionsAddress, USDC_BORROWED);
        IDebtToken(STABLE_DEBT_USDC).approveDelegation(migrateAavePositionsAddress, USDC_BORROWED);
        vm.stopPrank();

        vm.startPrank(BORROWER);
        flashloan.migrateAavePositions(
            RECEIVER, 
            debtTokenPositions, 
            aTokenPositions
        );


        (, , uint256 usdcReceiverVariableDebt, , , , , ,) = protocolDataProvider.getUserReserveData(USDC_ADDRESS, RECEIVER);
        (uint256 daiBorrowerATokenBalance, , , , , , , ,) = protocolDataProvider.getUserReserveData(DAI_ADDRESS, BORROWER);
        (uint256 daiReceiverATokenBalance, , , , , , , ,) = protocolDataProvider.getUserReserveData(DAI_ADDRESS, RECEIVER);

        // Rounding errors with "-1"
        assertEq(daiBorrowerATokenBalance, initialBorrowerDaiTokenBalance - amountDaiToTransfer - 1);
        // Lending positions transferred to RECEIVER account
        assertEq(amountDaiToTransfer, daiReceiverATokenBalance);

        // 0.09% = 9 / 10000
        uint256 flashloanFee = amountUsdcToTransfer * 9 / 10000;
        assertEq(usdcReceiverVariableDebt, amountUsdcToTransfer + flashloanFee);
    }

    // https://etherscan.io/address/0xeaf1890cac871f93c15009b7a05e2e5e076911e1?toaddress=0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9
    function test_migrateUsdcPositionsWithEthCollateral() public {
        address BORROWER = 0xEAf1890cAC871F93c15009b7A05e2E5E076911e1;
        vm.label(BORROWER, "Borrower");

        vm.startPrank(BORROWER); 
        DataTypes.DebtTokenPosition[] memory debtTokenPositions = new DataTypes.DebtTokenPosition[](1);
        DataTypes.aTokenPosition[] memory aTokenPositions = new DataTypes.aTokenPosition[](1);

        uint256 aStEthTokenAmount = aStEthToken.balanceOf(BORROWER);
        (, , uint usdcBorrowerVariableDebt, , uint usdcBorrowerScaledVariableDebt, , , ,) = protocolDataProvider.getUserReserveData(USDC_ADDRESS, BORROWER);

        aTokenPositions[0] = DataTypes.aTokenPosition({
            tokenAddress: ST_ETH_ADDRESS,
            aTokenAddress: A_ST_ETH_ADDRESS,
            amount: aStEthTokenAmount
        });

        debtTokenPositions[0] = DataTypes.DebtTokenPosition({
            stableDebtAmount: 0, 
            // Give buffer for flash loan fee (0.09%) -> 0.1% buffer
            variableDebtAmount: usdcBorrowerVariableDebt, 
            tokenAddress: USDC_ADDRESS
        });
        
        // Pre-approve aToken positions transfer on "sender" wallet
        IERC20(A_ST_ETH_ADDRESS).approve(
            migrateAavePositionsAddress, 
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(RECEIVER);
        // Pre-approve borrow positions on "RECEIVER" wallet
        IDebtToken(VARIABLE_DEBT_USDC).approveDelegation(
            migrateAavePositionsAddress, 
            usdcBorrowerVariableDebt
        );
        IDebtToken(STABLE_DEBT_USDC).approveDelegation(
            migrateAavePositionsAddress, 
            usdcBorrowerVariableDebt
        );
        vm.stopPrank();

        // Start flash loan
        vm.startPrank(BORROWER);
        flashloan.migrateAavePositions(
            RECEIVER, 
            debtTokenPositions, 
            aTokenPositions
        );
        vm.stopPrank();
    }    
}   