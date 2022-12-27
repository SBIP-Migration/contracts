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
    
    address private constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant A_WETH_ADDRESS = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;
    address private constant VARIABLE_DEBT_WETH = 0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf;

    address private constant WBTC_ADDRESS  = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant A_WBTC_ADDRESS = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;

    address private constant SNX_ADDRESS = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address private constant A_SNX_ADDRESS = 0x35f6B052C598d933D69A4EEC4D04c73A191fE6c2;

    // Collateral
    address private constant A_DAI_ADDRESS = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    // Collateral (underlying)
    address private constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

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

    // https://zapper.fi/account/scorched.eth/protocols/ethereum/aave-v2
    // Multiple debt positions (WETH & USDC)
    function test_migrateMultiplePositionsWithDaiCollateral() public {
        // https://etherscan.io/tx/0xb631bbbfa79b3f09eaa32a2e72e13c78aaac9880798bb50137baef7057d98b4c
        address BORROWER = 0xb6aF7C04f67B5eb61F0DC7aC4a760888EC3E3887;
        vm.label(BORROWER, "Borrower");

        vm.startPrank(BORROWER); 
        DataTypes.DebtTokenPosition[] memory debtTokenPositions = new DataTypes.DebtTokenPosition[](2);
        DataTypes.aTokenPosition[] memory aTokenPositions = new DataTypes.aTokenPosition[](1);

        (, , uint256 USDC_BORROWED, , , , , ,) = protocolDataProvider.getUserReserveData(USDC_ADDRESS, BORROWER);
        (, , uint256 WETH_BORROWED, , , , , ,) = protocolDataProvider.getUserReserveData(WETH_ADDRESS, BORROWER); // 7.49 WETH
        (uint256 DAI_LENDED, , , , , , , ,) = protocolDataProvider.getUserReserveData(DAI_ADDRESS, BORROWER);

        // USDC debt
        debtTokenPositions[0] = DataTypes.DebtTokenPosition({
            stableDebtAmount: 0, 
            variableDebtAmount: USDC_BORROWED, 
            tokenAddress: USDC_ADDRESS
        });

        // WETH debt
        debtTokenPositions[1] = DataTypes.DebtTokenPosition({
            stableDebtAmount: 0,
            variableDebtAmount: WETH_BORROWED,
            tokenAddress: WETH_ADDRESS
        });
        
        // DAI collateral
        aTokenPositions[0] = DataTypes.aTokenPosition({
            tokenAddress: DAI_ADDRESS,
            aTokenAddress: A_DAI_ADDRESS,
            amount: DAI_LENDED
        });

        // Pre-approve aToken positions transfer on "sender" wallet
        IERC20(A_DAI_ADDRESS).approve(
            migrateAavePositionsAddress, 
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(RECEIVER);
        // Pre-approve borrow positions on "RECEIVER" wallet
        IDebtToken(VARIABLE_DEBT_USDC).approveDelegation(migrateAavePositionsAddress, type(uint256).max);
        IDebtToken(VARIABLE_DEBT_WETH).approveDelegation(migrateAavePositionsAddress, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(BORROWER);
        flashloan.migrateAavePositions(
            RECEIVER, 
            debtTokenPositions, 
            aTokenPositions
        );

        // Receiver related
        (, , uint256 usdcReceiverVariableDebt, , , , , ,) = protocolDataProvider.getUserReserveData(USDC_ADDRESS, RECEIVER);
        (, , uint256 wethReceiverVariableDebt, , , , , ,) = protocolDataProvider.getUserReserveData(WETH_ADDRESS, RECEIVER);
        (uint256 daiReceiverATokenBalance, , , , , , , ,) = protocolDataProvider.getUserReserveData(DAI_ADDRESS, RECEIVER);

        // Lending positions transferred to RECEIVER account
        assertEq(DAI_LENDED, daiReceiverATokenBalance);

        // 0.09% = 9 / 10000
        uint256 flashloanFeeUsdc = USDC_BORROWED * 9 / 10000;
        uint256 flashloanFeeWeth = WETH_BORROWED * 9 / 10000;
        assertEq(usdcReceiverVariableDebt, USDC_BORROWED + flashloanFeeUsdc);
        assertEq(wethReceiverVariableDebt, WETH_BORROWED + flashloanFeeWeth);
    }

    // https://etherscan.io/address/0xeaf1890cac871f93c15009b7a05e2e5e076911e1?toaddress=0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9
    // Single debt position (USDC)
    function test_migrateUsdcPositionsWithEthCollateral() public {
        address BORROWER = 0xEAf1890cAC871F93c15009b7A05e2E5E076911e1;
        vm.label(BORROWER, "Borrower");

        vm.startPrank(BORROWER); 
        DataTypes.DebtTokenPosition[] memory debtTokenPositions = new DataTypes.DebtTokenPosition[](1);
        DataTypes.aTokenPosition[] memory aTokenPositions = new DataTypes.aTokenPosition[](1);

        (uint ST_ETH_LENDED, , , , , , , ,) = protocolDataProvider.getUserReserveData(ST_ETH_ADDRESS, BORROWER);
        (, , uint USDC_BORROWED, , , , , ,) = protocolDataProvider.getUserReserveData(USDC_ADDRESS, BORROWER);

        aTokenPositions[0] = DataTypes.aTokenPosition({
            tokenAddress: ST_ETH_ADDRESS,
            aTokenAddress: A_ST_ETH_ADDRESS,
            amount: ST_ETH_LENDED
        });

        debtTokenPositions[0] = DataTypes.DebtTokenPosition({
            stableDebtAmount: 0, 
            // Give buffer for flash loan fee (0.09%) -> 0.1% buffer
            variableDebtAmount: USDC_BORROWED, 
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
            USDC_BORROWED
        );
        IDebtToken(STABLE_DEBT_USDC).approveDelegation(
            migrateAavePositionsAddress, 
            USDC_BORROWED
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

        (, , uint256 usdcReceiverVariableDebt, , , , , ,) = protocolDataProvider.getUserReserveData(USDC_ADDRESS, RECEIVER);
        (uint256 stEthReceiverATokenBalance, , , , , , , ,) = protocolDataProvider.getUserReserveData(ST_ETH_ADDRESS, RECEIVER);

        // Rounding errors with "-1"
        assertEq(stEthReceiverATokenBalance, ST_ETH_LENDED - 1);

        uint256 flashloanFee = USDC_BORROWED * 9 / 10000;
        assertEq(usdcReceiverVariableDebt, USDC_BORROWED + flashloanFee);
    }    

    // Multiple lending positions
    // https://zapper.fi/account/0x0B5a6a15B975fD35f0B301748C8DaBD35b50d8C5/protocols/ethereum/aave-v2
    function testMigrateMultipleLendingPositions() public {
        address BORROWER = 0x0B5a6a15B975fD35f0B301748C8DaBD35b50d8C5;
        vm.label(BORROWER, "Borrower");

        vm.startPrank(BORROWER); 
        DataTypes.DebtTokenPosition[] memory debtTokenPositions = new DataTypes.DebtTokenPosition[](1);
        DataTypes.aTokenPosition[] memory aTokenPositions = new DataTypes.aTokenPosition[](3);

        (uint WETH_LENDED, , , , , , , ,) = protocolDataProvider.getUserReserveData(WETH_ADDRESS, BORROWER);
        (uint WBTC_LENDED, , , , , , , ,) = protocolDataProvider.getUserReserveData(WBTC_ADDRESS, BORROWER);
        (uint SNX_LENDED, , , , , , , ,) = protocolDataProvider.getUserReserveData(SNX_ADDRESS, BORROWER);

        (, , uint USDC_BORROWED, , , , , ,) = protocolDataProvider.getUserReserveData(USDC_ADDRESS, BORROWER);

        aTokenPositions[0] = DataTypes.aTokenPosition({
            tokenAddress: WETH_ADDRESS,
            aTokenAddress: A_WETH_ADDRESS,
            amount: WETH_LENDED
        });
        
        aTokenPositions[1] = DataTypes.aTokenPosition({
            tokenAddress: WBTC_ADDRESS,
            aTokenAddress: A_WBTC_ADDRESS,
            amount: WBTC_LENDED
        });
        
        aTokenPositions[2] = DataTypes.aTokenPosition({
            tokenAddress: SNX_ADDRESS,
            aTokenAddress: A_SNX_ADDRESS,
            amount: SNX_LENDED
        });

        debtTokenPositions[0] = DataTypes.DebtTokenPosition({
            stableDebtAmount: 0, 
            // Give buffer for flash loan fee (0.09%) -> 0.1% buffer
            variableDebtAmount: USDC_BORROWED, 
            tokenAddress: USDC_ADDRESS
        });
        
        // Pre-approve aToken positions transfer on "sender" wallet
        IERC20(A_WETH_ADDRESS).approve(
            migrateAavePositionsAddress, 
            type(uint256).max
        );
        
        IERC20(A_WBTC_ADDRESS).approve(
            migrateAavePositionsAddress, 
            type(uint256).max
        );
        
        IERC20(A_SNX_ADDRESS).approve(
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

        // Start flash loan
        vm.startPrank(BORROWER);
        flashloan.migrateAavePositions(
            RECEIVER, 
            debtTokenPositions, 
            aTokenPositions
        );
        vm.stopPrank();

        (uint WETH_LENDED_RECEIVER, , , , , , , ,) = protocolDataProvider.getUserReserveData(WETH_ADDRESS, RECEIVER);
        (uint WBTC_LENDED_RECEIVER, , , , , , , ,) = protocolDataProvider.getUserReserveData(WBTC_ADDRESS, RECEIVER);
        (uint SNX_LENDED_RECEIVER, , , , , , , ,) = protocolDataProvider.getUserReserveData(SNX_ADDRESS, RECEIVER);

        (, , uint USDC_BORROWED_RECEIVER, , , , , ,) = protocolDataProvider.getUserReserveData(USDC_ADDRESS, RECEIVER);

        // Check lending positions (transferred)
        assertEq(WETH_LENDED_RECEIVER, WETH_LENDED);
        assertEq(WBTC_LENDED_RECEIVER, WBTC_LENDED);
        assertEq(SNX_LENDED_RECEIVER, SNX_LENDED);

        uint256 flashloanFee = USDC_BORROWED * 9 / 10000;
        // Rounding errors in division, with "-1"
        assertEq(USDC_BORROWED_RECEIVER, USDC_BORROWED + flashloanFee - 1);
    }
}   