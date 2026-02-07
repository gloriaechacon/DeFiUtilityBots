import { writeContract, waitForTransactionReceipt, readContract } from "@wagmi/core";
import { parseUnits } from "viem";
import { wagmiConfig } from "../../wallet/wagmi";
import { EXPENSE_VAULT_ABI, EXPENSE_VAULT_ADDRESS } from "../lib/contracts/expense-vault";
import type { VaultAdapter } from "./vault-adapter";

const USDC_DECIMALS = 6;

function toUsdcUnits(amountUsdc: string) {
  return parseUnits(amountUsdc, USDC_DECIMALS);
}

function calculateSharesForWithdrawal(usdcAmount: bigint, totalShares: bigint, totalAssets: bigint
) {
  return (usdcAmount * totalShares + totalAssets - 1n) / totalAssets;
}

export function createWagmiVaultAdapter(ownerAddress?: `0x${string}`): VaultAdapter {
  return {
    async fund(amountUsdc: string) {
      const amount = toUsdcUnits(amountUsdc);

      const hash = await writeContract(wagmiConfig, {
        address: EXPENSE_VAULT_ADDRESS,
        abi: EXPENSE_VAULT_ABI,
        functionName: "deposit",
        args: [amount],
      });

      await waitForTransactionReceipt(wagmiConfig, { hash });
    },

    async withdraw(amountUsdc: string) {
      if (!ownerAddress) {
        throw new Error("Wallet not connected");
      }

      const amount = toUsdcUnits(amountUsdc);

      if (amount <= 0n) throw new Error("Invalid amount");

      const [totalSupply, totalAssets, userShares] = await Promise.all([
        readContract(wagmiConfig, {
          address: EXPENSE_VAULT_ADDRESS,
          abi: EXPENSE_VAULT_ABI,
          functionName: "totalSupply",
        }) as Promise<bigint>,
        readContract(wagmiConfig, {
          address: EXPENSE_VAULT_ADDRESS,
          abi: EXPENSE_VAULT_ABI,
          functionName: "totalAssets",
        }) as Promise<bigint>,
        readContract(wagmiConfig, {
          address: EXPENSE_VAULT_ADDRESS,
          abi: EXPENSE_VAULT_ABI,
          functionName: "balanceOf",
          args: [ownerAddress],
        }) as Promise<bigint>,
      ]);

      if (totalSupply === 0n || totalAssets === 0n) {
        throw new Error("Vault is empty");
      }
      
      let sharesToWithdraw = calculateSharesForWithdrawal(amount, totalSupply, totalAssets);

      if (sharesToWithdraw > userShares) sharesToWithdraw = userShares;
      if (sharesToWithdraw <= 0n) throw new Error("Insufficient shares");

      const hash = await writeContract(wagmiConfig, {
        address: EXPENSE_VAULT_ADDRESS,
        abi: EXPENSE_VAULT_ABI,
        functionName: "withdraw",
        args: [amount],
      });

      await waitForTransactionReceipt(wagmiConfig, { hash });
    },
  };
}