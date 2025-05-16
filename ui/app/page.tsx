"use client";
import { useState, useEffect } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount, useWalletClient } from "wagmi";
import { usePublicClient } from "wagmi";
import { ethers } from "ethers";
import { HOOKTUAH_ABI, HOOKTUAH_ADDRESS, approveToken0, approveToken1 } from "../lib/contract";
import { readContract, writeContract } from "@wagmi/core";

export default function Home() {
  const { address, isConnected } = useAccount();
  const { data: walletClient } = useWalletClient();
  const publicClient = usePublicClient();

  const [token0Balance, setToken0Balance] = useState<string>("-");
  const [token1Balance, setToken1Balance] = useState<string>("-");
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [isToken0, setIsToken0] = useState(true);
  const [loading, setLoading] = useState(false);
  const [txStatus, setTxStatus] = useState<string | null>(null);
  const [approve0Loading, setApprove0Loading] = useState(false);
  const [approve1Loading, setApprove1Loading] = useState(false);
  const [approve0Status, setApprove0Status] = useState<string | null>(null);
  const [approve1Status, setApprove1Status] = useState<string | null>(null);

  // Fetch balances
  useEffect(() => {
    if (!address || !publicClient) {
      setToken0Balance("-");
      setToken1Balance("-");
      return;
    }
    readContract({
      address: HOOKTUAH_ADDRESS,
      abi: HOOKTUAH_ABI,
      functionName: "token0Balance",
      args: [address],
    })
      .then((bal) => setToken0Balance(ethers.formatUnits(bal as bigint, 18)))
      .catch(() => setToken0Balance("-"));
    readContract({
      address: HOOKTUAH_ADDRESS,
      abi: HOOKTUAH_ABI,
      functionName: "token1Balance",
      args: [address],
    })
      .then((bal) => setToken1Balance(ethers.formatUnits(bal as bigint, 18)))
      .catch(() => setToken1Balance("-"));
  }, [address, publicClient, txStatus]);

  // Handle deposit
  async function handleDeposit(e: React.FormEvent) {
    e.preventDefault();
    if (!walletClient || !depositAmount) return;
    setLoading(true);
    setTxStatus(null);
    try {
      const hash = await writeContract({
        address: HOOKTUAH_ADDRESS,
        abi: HOOKTUAH_ABI,
        functionName: "deposit",
        args: [ethers.parseUnits(depositAmount, 18), isToken0],
        account: address,
      });
      setTxStatus("Pending...");
      // Optionally, you can wait for confirmation here using publicClient.waitForTransactionReceipt({hash})
      setTxStatus("Deposit successful!");
      setDepositAmount("");
    } catch (err: any) {
      setTxStatus("Deposit failed: " + (err.message || "Unknown error"));
    } finally {
      setLoading(false);
    }
  }

  // Handle withdraw
  async function handleWithdraw(e: React.FormEvent) {
    e.preventDefault();
    if (!walletClient || !withdrawAmount) return;
    setLoading(true);
    setTxStatus(null);
    try {
      const hash = await writeContract({
        address: HOOKTUAH_ADDRESS,
        abi: HOOKTUAH_ABI,
        functionName: "withdraw",
        args: [ethers.parseUnits(withdrawAmount, 18), isToken0],
        account: address,
      });
      setTxStatus("Pending...");
      // Optionally, you can wait for confirmation here using publicClient.waitForTransactionReceipt({hash})
      setTxStatus("Withdraw successful!");
      setWithdrawAmount("");
    } catch (err: any) {
      setTxStatus("Withdraw failed: " + (err.message || "Unknown error"));
    } finally {
      setLoading(false);
    }
  }

  async function handleApproveToken0() {
    if (!address) {
      setApprove0Status("Connect wallet first!");
      return;
    }
    setApprove0Loading(true);
    setApprove0Status(null);
    try {
      await approveToken0(address);
      setApprove0Status("Token0 approval successful!");
    } catch (e: any) {
      setApprove0Status("Token0 approval failed: " + (e.message || "Unknown error"));
    } finally {
      setApprove0Loading(false);
    }
  }
  async function handleApproveToken1() {
    if (!address) {
      setApprove1Status("Connect wallet first!");
      return;
    }
    setApprove1Loading(true);
    setApprove1Status(null);
    try {
      await approveToken1(address);
      setApprove1Status("Token1 approval successful!");
    } catch (e: any) {
      setApprove1Status("Token1 approval failed: " + (e.message || "Unknown error"));
    } finally {
      setApprove1Loading(false);
    }
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-screen p-6 gap-8">
      <h1 className="text-2xl font-bold mb-2">HookTuah UI</h1>
      <ConnectButton />
      {isConnected && (
        <div className="w-full max-w-md mt-6 flex flex-col gap-6">
          <div className="flex gap-4">
            <button
              className={`bg-blue-600 text-white px-4 py-2 rounded ${approve0Loading ? "opacity-60" : ""}`}
              onClick={handleApproveToken0}
              disabled={approve0Loading}
            >
              {approve0Loading ? "Approving Token0..." : "Approve Token0"}
            </button>
            <button
              className={`bg-blue-600 text-white px-4 py-2 rounded ${approve1Loading ? "opacity-60" : ""}`}
              onClick={handleApproveToken1}
              disabled={approve1Loading}
            >
              {approve1Loading ? "Approving Token1..." : "Approve Token1"}
            </button>
          </div>
          {approve0Status && <div className="text-center text-sm">{approve0Status}</div>}
          {approve1Status && <div className="text-center text-sm">{approve1Status}</div>}
          <div className="flex flex-col gap-2">
            <div>
              <span className="font-mono">token0 balance:</span> {token0Balance}
            </div>
            <div>
              <span className="font-mono">token1 balance:</span> {token1Balance}
            </div>
          </div>

          <div className="flex gap-4">
            <button className={`px-3 py-1 rounded ${isToken0 ? "bg-blue-500 text-white" : "bg-gray-200"}`} onClick={() => setIsToken0(true)} disabled={loading}>Token0</button>
            <button className={`px-3 py-1 rounded ${!isToken0 ? "bg-blue-500 text-white" : "bg-gray-200"}`} onClick={() => setIsToken0(false)} disabled={loading}>Token1</button>
          </div>

          <form className="flex flex-col gap-2" onSubmit={handleDeposit}>
            <label className="font-semibold">Deposit</label>
            <input
              type="number"
              min="0"
              step="any"
              className="border rounded px-2 py-1"
              placeholder="Amount"
              value={depositAmount}
              onChange={e => setDepositAmount(e.target.value)}
              disabled={loading}
            />
            <button className="bg-green-500 text-white px-4 py-2 rounded" type="submit" disabled={loading || !depositAmount}>Deposit {isToken0 ? "Token0" : "Token1"}</button>
          </form>

          <form className="flex flex-col gap-2" onSubmit={handleWithdraw}>
            <label className="font-semibold">Withdraw</label>
            <input
              type="number"
              min="0"
              step="any"
              className="border rounded px-2 py-1"
              placeholder="Amount"
              value={withdrawAmount}
              onChange={e => setWithdrawAmount(e.target.value)}
              disabled={loading}
            />
            <button className="bg-red-500 text-white px-4 py-2 rounded" type="submit" disabled={loading || !withdrawAmount}>Withdraw {isToken0 ? "Token0" : "Token1"}</button>
          </form>

          {txStatus && <div className="mt-2 text-center text-sm">{txStatus}</div>}
        </div>
      )}
    </div>
  );
}
