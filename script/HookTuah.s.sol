// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Constants} from "./base/Constants.sol"; // Adjust path as needed
import {HookTuah} from "../src/HookTuah.sol";   // Adjust path as needed

contract DeployHookTuah is Script, Constants {
    function setUp() public {}

    function run() public {
        // Set the flags for the callbacks your hook implements
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
            Hooks.AFTER_ADD_LIQUIDITY_FLAG |
            Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );

        // Set your token addresses here
        address token0 = 0xdD37D4a3F585af19C66291151537002012c90CB2;
        address token1 = 0x3f6ad5DB52D7Ed9879532a40558851078a7f4496;

        bytes memory constructorArgs = abi.encode(IPoolManager(POOLMANAGER), token0, token1);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(HookTuah).creationCode, constructorArgs);

        vm.broadcast();
        HookTuah hook = new HookTuah{salt: salt}(IPoolManager(POOLMANAGER), token0, token1);
        require(address(hook) == hookAddress, "HookTuahScript: hook address mismatch");
    }
}