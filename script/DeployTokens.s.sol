// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/Token0.sol";
import "../src/Token1.sol";

contract DeployTokens is Script {
    function run() external {
        vm.startBroadcast();

        Token0 token0 = new Token0();
        Token1 token1 = new Token1();

        console.log("Token0 address:", address(token0));
        console.log("Token1 address:", address(token1));

        vm.stopBroadcast();
    }
}
