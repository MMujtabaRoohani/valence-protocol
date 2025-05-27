// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../../src/accounts/Account.sol" as ValenceAccount;
import {Test, console} from "forge-std/src/Test.sol";
import {Splitter} from "../../src/libraries/Splitter.sol";
import {IERC20} from "forge-std/src/interfaces/IERC20.sol";
import {BaseAccount} from "../../src/accounts/BaseAccount.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";

contract SplitterTest is Test {
    // Contract under test
    Splitter public splitter;

    // config params
    Splitter.SplitConfig[] splits;

    // Mock contracts
    ValenceAccount.Account public inputAccount;
    ValenceAccount.Account public outputAccount;
    MockERC20 public token;

    // Test addresses
    address public owner;
    address public processor;
    uint16 public referralCode = 0;

    // Setup function to initialize test environment
    function setUp() public {
        // Setup test addresses
        owner = makeAddr("owner");
        processor = makeAddr("processor");

        // Deploy mock tokens
        token = new MockERC20();

        // Create mock accounts
        inputAccount = new BaseAccount(owner, new address[](0));
        outputAccount = new BaseAccount(owner, new address[](0));

        // Create sample splits
        splits = new Splitter.SplitConfig[](1);
        splits[0] = Splitter.SplitConfig({
            outputAccount: outputAccount,
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedAmount,
            amount: abi.encode(1)
        });

        // Deploy Splitter contract
        // Create and encode config directly
        Splitter.SplitterConfig memory config = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: splits
        });

        splitter = new Splitter(owner, processor, abi.encode(config));

        vm.prank(owner);
        inputAccount.approveLibrary(address(splitter));
    }

    // ============== Configuration Tests ==============

    // Test configuration validation
    function test_GivenConfigIsValid_WhenOwnerUpdateConfig_ThenUpdateInputAccount() public {
        // given
        ValenceAccount.Account newInputAccount = new BaseAccount(owner, new address[](0));
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: newInputAccount,
            splits: splits
        });

        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));

        // then
        (ValenceAccount.Account actualInputAccount) = splitter.config();
        assertEq(address(actualInputAccount), address(newInputAccount));
    }

    function test_RevertUpdateConfig_WithUnauthorized_WhenNotOwnerUpdateConfig() public {
        // given
        address unauthorized = makeAddr("unauthorized");
        Splitter.SplitterConfig memory config = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: new Splitter.SplitConfig[](0)
        });

        // expect
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized));
        
        // when
        vm.prank(unauthorized);
        splitter.updateConfig(abi.encode(config));
    }

    function test_RevertUpdateConfig_WithEmptySplitsConfig_WhenSplitsArrayIsEmpty() public {
        // given
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: new Splitter.SplitConfig[](0)
        });

        // expect
        vm.expectRevert("No split configuration provided.");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }

    function test_RevertUpdateConfig_WithDuplicateSplit_WhenSplitsArrayHasTwoIdenticalEntries() public {
        // given
        Splitter.SplitConfig[] memory duplicateSplits = new Splitter.SplitConfig[](2);
        duplicateSplits[0] = Splitter.SplitConfig({
            outputAccount: outputAccount,
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedAmount,
            amount: abi.encode(1)
        });
        duplicateSplits[1] = Splitter.SplitConfig({
            outputAccount: outputAccount,
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedAmount,
            amount: abi.encode(1)
        });
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: duplicateSplits
        });

        // expect
        vm.expectRevert("Duplicate split in split config.");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }

    function test_RevertUpdateConfig_WithInvalidAmount_WhenFixedAmountSplitHasZeroAmount() public {
        // given
        Splitter.SplitConfig[] memory zeroAmountSplit = new Splitter.SplitConfig[](1);
        zeroAmountSplit[0] = Splitter.SplitConfig({
            outputAccount: outputAccount,
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedAmount,
            amount: abi.encode(0)
        });
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: zeroAmountSplit
        });

        // expect
        vm.expectRevert("Invalid split config: amount cannot be zero.");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }

    function test_RevertUpdateConfig_WithInvalidRatio_WhenFixedRatioSplitHasZeroRatio() public {
        // given
        Splitter.SplitConfig[] memory zeroRatioSplit = new Splitter.SplitConfig[](1);
        zeroRatioSplit[0] = Splitter.SplitConfig({
            outputAccount: outputAccount,
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(0)
        });
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: zeroRatioSplit
        });

        // expect
        vm.expectRevert("Invalid split config: ratio cannot be zero.");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }

    function test_RevertUpdateConfig_WithInvalidRatio_WhenFixedRatioSplitsSumIsGreaterThanOne() public {
        // given
        Splitter.SplitConfig[] memory gt1RatioSplit = new Splitter.SplitConfig[](3);
        gt1RatioSplit[0] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(1_000_000_000_000_000_000)
        });
        gt1RatioSplit[1] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(1_000_000_000_000_000_000)
        });
        gt1RatioSplit[2] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(1_000_000_000_000_000_000)
        });
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: gt1RatioSplit
        });

        // expect
        vm.expectRevert("Invalid split config: sum of ratios is not equal to 1.");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }

    function test_RevertUpdateConfig_WithInvalidRatio_WhenFixedRatioSplitsSumIsLessThanOne() public {
        // given
        Splitter.SplitConfig[] memory lt1RatioSplit = new Splitter.SplitConfig[](3);
        lt1RatioSplit[0] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(333_000_000_000_000_000)
        });
        lt1RatioSplit[1] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(333_000_000_000_000_000)
        });
        lt1RatioSplit[2] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(333_000_000_000_000_000)
        });
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: lt1RatioSplit
        });

        // expect
        vm.expectRevert("Invalid split config: sum of ratios is not equal to 1.");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }

    function test_RevertUpdateConfig_WithConflictingSplitType_WhenSplitsHasAmountAndRatioTypesCombined() public {
        // given
        Splitter.SplitConfig[] memory conflictingSplits = new Splitter.SplitConfig[](2);
        conflictingSplits[0] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(1_000_000_000_000_000_000)
        });
        conflictingSplits[1] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedAmount,
            amount: abi.encode(1_000_000_000_000_000_000)
        });
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: conflictingSplits
        });

        // expect
        vm.expectRevert("Invalid split config: cannot combine different split types for same token.");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }

    function test_RevertUpdateConfig_WithConflictingSplitType_WhenSplitsHasFixedAndDynamicRatioTypesCombined() public {
        // given
        Splitter.SplitConfig[] memory conflictingSplits = new Splitter.SplitConfig[](2);
        Splitter.DynamicRatioAmount memory dynamicRatioAmount = Splitter.DynamicRatioAmount({
            contractAddress: address(this),
            params: ""
        });
        conflictingSplits[0] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.DynamicRatio,
            amount: abi.encode(dynamicRatioAmount)
        });
        conflictingSplits[1] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.FixedRatio,
            amount: abi.encode(1_000_000_000_000_000_000)
        });

        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: conflictingSplits
        });

        // expect
        vm.expectRevert("Invalid split config: cannot combine different split types for same token.");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }

    function test_RevertUpdateConfig_WithInvalidSplitConfig_WhenDynamicRatioSplitHasNonContractAddress() public {
        // given
        Splitter.DynamicRatioAmount memory dynamicRatioAmount = Splitter.DynamicRatioAmount({
            contractAddress: makeAddr("randomEOA"),
            params: ""
        });
        Splitter.SplitConfig[] memory amountAndRatioSplit = new Splitter.SplitConfig[](1);
        amountAndRatioSplit[0] = Splitter.SplitConfig({
            outputAccount: new BaseAccount(owner, new address[](0)),
            token: IERC20(token),
            splitType: Splitter.SplitType.DynamicRatio,
            amount: abi.encode(dynamicRatioAmount)
        });
        Splitter.SplitterConfig memory newConfig = Splitter.SplitterConfig({
            inputAccount: inputAccount,
            splits: amountAndRatioSplit
        });

        // expect
        vm.expectRevert("Invalid split config: dynamic ratio contract address is not a contract");
        
        // when
        vm.prank(owner);
        splitter.updateConfig(abi.encode(newConfig));
    }
}