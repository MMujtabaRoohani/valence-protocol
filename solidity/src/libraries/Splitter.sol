// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Library} from "./Library.sol";
import {Account} from "../accounts/Account.sol";
import {IERC20} from "forge-std/src/interfaces/IERC20.sol";

/**
 * @title Splitter
 * @dev The Valence Splitter library allows to split funds from one input account to one or more output account(s), 
 * for one or more token denom(s) according to the configured ratio(s). 
 * It is typically used as part of a Valence Program. In that context, 
 * a Processor contract will be the main contract interacting with the Splitter library.
 */
contract Splitter is Library {
    uint256 public constant DECIMALS = 18;


    /**
     * @title SplitterConfig
     * @notice Configuration struct for Aave lending operations
     * @dev Defines splitting parameters 
     * @param inputAccount Address of the input account
     * @param splits Split configuration per token address
     */
    struct SplitterConfig {
        Account inputAccount;
        SplitConfig[] splits;
    }

    /**
     * @title SplitConfig
     * @notice Split config for specified account
     * @dev Used to define the split config for a token to an account
     * @param outputAccount Address of the output account
     * @param token Address of the output account
     * @param splitType type of the split
     * @param amount encoded configuration based on the type of split
     */
    struct SplitConfig {
        Account outputAccount;
        IERC20 token;
        SplitType splitType;
        bytes amount;
    }

    /**
     * @title SplitType
     * @notice enum defining allowed variants of split config
     */
    enum SplitType {
        FixedAmount,
        FixedRatio,
        DynamicRatio
    }

    /**
     * @title DynamicRatioAmount
     * @notice Params for dynamic ratio split 
     * @dev Used to define the config when split type is DynamicRatio
     * @param outputAccount Address of the output account
     * @param token Address of the output account
     * @param splitType type of the split
     * @param amount encoded configuration based on the type of split
     */
    struct DynamicRatioAmount {
        address contractAddress;
        bytes params;
    }

    /// @notice Holds the current configuration for the Splitter.
    SplitterConfig public config;

    /// @notice Holds the splitConfig against output account against split token.
    mapping(IERC20 => mapping(Account => SplitConfig)) splitConfigMapping;
    mapping(IERC20 => uint256) tokenRatioSplitSum;
    mapping(IERC20 => uint256) tokenAmountSplitSum;

    /**
     * @dev Constructor initializes the contract with the owner, processor, and initial configuration.
     * @param _owner Address of the contract owner.
     * @param _processor Address of the processor that can execute functions.
     * @param _config Encoded configuration parameters for the AavePositionManager.
     */
    constructor(address _owner, address _processor, bytes memory _config) Library(_owner, _processor, _config) {}

    /**
     * @notice Validates the provided configuration parameters
     * @dev Checks for validity of input account, and splits
     * @param _config The encoded configuration bytes to validate
     * @return SplitterConfig A validated configuration struct
     */
    function validateConfig(bytes memory _config) internal returns (SplitterConfig memory) {
        // Decode the configuration bytes into the AavePositionManagerConfig struct.
        SplitterConfig memory decodedConfig = abi.decode(_config, (SplitterConfig));

        // Ensure the input account address is valid (non-zero).
        if (decodedConfig.inputAccount == Account(payable(address(0)))) {
            revert("Input account can't be zero address");
        }

        deleteSplitsInState();
        validateSplits(decodedConfig.splits);

        return decodedConfig;
    }

    /**
     * @notice Validates the provided splits configuration
     * @dev Checks for duplicate split, sum of ratios to 1 and dynamic ratio contract address to be valid smart contract
     * @param splits The array of SplitConfig to validate
     */
    function validateSplits(SplitConfig[] memory splits) internal {
        require(splits.length > 0, "No split configuration provided.");

        for (uint256 i = 0; i < splits.length; i++) {
            SplitConfig memory split = splits[i];
            
            if (address(splitConfigMapping[split.token][split.outputAccount].outputAccount) != address(0)) {
                revert("Duplicate split in split config.");
            }

            if(split.splitType == SplitType.FixedAmount) {
                uint256 decodedAmount = abi.decode(split.amount, (uint256));
                require(decodedAmount > 0, "Invalid split config: amount cannot be zero.");

                tokenAmountSplitSum[split.token] += decodedAmount;
            } else if(split.splitType == SplitType.FixedRatio) {
                uint256 decodedAmount = abi.decode(split.amount, (uint256));
                require(decodedAmount > 0, "Invalid split config: ratio cannot be zero.");

                tokenRatioSplitSum[split.token] += decodedAmount;
            } else {
                DynamicRatioAmount memory dynamicRatioAmount = abi.decode(split.amount, (DynamicRatioAmount));
                require(tokenAmountSplitSum[split.token] == 0 && tokenRatioSplitSum[split.token] == 0, "Invalid split config: cannot combine different split types for same token.");
                require(dynamicRatioAmount.contractAddress.code.length > 0, "Invalid split config: dynamic ratio contract address is not a contract");
            }

            splitConfigMapping[split.token][split.outputAccount] = split;
        }
        
        // checking if sum of all ratios is 1 and conflicting types are not provided
        for (uint256 i = 0; i < splits.length; i++) {
            SplitConfig memory split = splits[i];
            
            if(split.splitType == SplitType.FixedAmount) {
                require(tokenRatioSplitSum[split.token] == 0, "Invalid split config: cannot combine different split types for same token.");
            } else if(split.splitType == SplitType.FixedRatio) {
                require(tokenRatioSplitSum[split.token] == 10 ** DECIMALS, "Invalid split config: sum of ratios is not equal to 1.");
                require(tokenAmountSplitSum[split.token] == 0, "Invalid split config: cannot combine different split types for same token.");
            } else {
                require(tokenAmountSplitSum[split.token] == 0 && tokenRatioSplitSum[split.token] == 0, "Invalid split config: cannot combine different split types for same token.");
            }
        }
    }

    /**
     * @notice deletes the existing splits in state
     * @dev Useful to be used before updating config
     */
    function deleteSplitsInState() internal {
        for (uint256 i = 0; i < config.splits.length; i++) {
            SplitConfig memory split = config.splits[i];
            
            delete tokenRatioSplitSum[split.token];
            delete tokenAmountSplitSum[split.token];
            delete splitConfigMapping[split.token][split.outputAccount];
        }
    }

    /**
     * @dev Internal initialization function called during construction
     * @param _config New configuration
     */
    function _initConfig(bytes memory _config) internal override {
        config = validateConfig(_config);
    }

    /**
     * @dev Updates the Splitter configuration.
     * Only the contract owner is authorized to call this function.
     * @param _config New encoded configuration parameters.
     */
    function updateConfig(bytes memory _config) public override onlyOwner {
        // Validate and update the configuration.
        config = validateConfig(_config);
    }
}
