// Deployed contract address on Base Sepolia
export const HOOKTUAH_ADDRESS = "0xE73C81b5386aa1E90a74A1cbF8c9C6bB45461540";
export const TOKEN0_ADDRESS = "0xdD37D4a3F585af19C66291151537002012c90CB2";
export const TOKEN1_ADDRESS = "0x3f6ad5DB52D7Ed9879532a40558851078a7f4496";

export const ERC20_ABI = [
  {
    "constant": false,
    "inputs": [
      { "name": "_spender", "type": "address" },
      { "name": "_value", "type": "uint256" }
    ],
    "name": "approve",
    "outputs": [
      { "name": "success", "type": "bool" }
    ],
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [ { "name": "_owner", "type": "address" } ],
    "name": "balanceOf",
    "outputs": [ { "name": "balance", "type": "uint256" } ],
    "type": "function"
  },
];

// Approve HookTuah to spend Token0
import { writeContract } from "@wagmi/core";

export async function approveToken0(account: string, amount: bigint = BigInt("1000000000000000000000000")) {
  return writeContract({
    address: TOKEN0_ADDRESS,
    abi: ERC20_ABI,
    functionName: "approve",
    args: [HOOKTUAH_ADDRESS, amount],
    account,
  });
}

// Approve HookTuah to spend Token1
export async function approveToken1(account: string, amount: bigint = BigInt("1000000000000000000000000")) {
  return writeContract({
    address: TOKEN1_ADDRESS,
    abi: ERC20_ABI,
    functionName: "approve",
    args: [HOOKTUAH_ADDRESS, amount],
    account,
  });
}

// Minimal ABI for deposit, withdraw, and balance queries
export const HOOKTUAH_ABI = [
  {
    "inputs": [{ "internalType": "address", "name": "", "type": "address" }],
    "name": "token0Balance",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "address", "name": "", "type": "address" }],
    "name": "token1Balance",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "uint256", "name": "amount", "type": "uint256" },
      { "internalType": "bool", "name": "isToken0", "type": "bool" }
    ],
    "name": "deposit",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "uint256", "name": "amount", "type": "uint256" },
      { "internalType": "bool", "name": "isToken0", "type": "bool" }
    ],
    "name": "withdraw",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
];
