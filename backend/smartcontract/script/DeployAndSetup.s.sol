// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import "../src/ExpenseVault.sol";
import "../src/SimulatedLiquidityPool.sol";
import "../src/LiquidityPoolStrategy.sol";

contract DeployAndSetup is Script {
    // Base Sepolia USDC (your faucet token)
    address constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external {
        /**
         * ENV required:
         * - DEPLOYER_PRIVATE_KEY : broadcasts txs
         *
         * ENV optional:
         * - TOKEN_ADDRESS        : defaults to Base Sepolia USDC
         * - OWNER_PRIVATE_KEY    : used to sign EIP-712 policy/merchant permits (can be same as deployer)
         * - OWNER_ADDRESS        : if set, script checks OWNER_PRIVATE_KEY matches it
         * - SPENDER_ADDRESS      : defaults to deployer
         * - MERCHANT_ADDRESS     : defaults to deployer
         * - ANNUAL_RATE_BPS      : defaults to 500 (5%)
         * - DO_DEPOSIT           : "true"/"false" (default false)
         * - DEPOSIT_AMOUNT       : defaults to 200e6 (200 USDC)
         * - MAX_PER_TX           : defaults to 20e6
         * - DAILY_LIMIT          : defaults to 40e6
         * - WHITELIST            : "true"/"false" (default true)
         */

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        address tokenAddr = vm.envOr("TOKEN_ADDRESS", BASE_SEPOLIA_USDC);

        uint256 annualRateBps = vm.envOr("ANNUAL_RATE_BPS", uint256(500)); // 5% APY simulated

        // Addresses for policy demo
        address spender = vm.envOr("SPENDER_ADDRESS", deployer);
        address merchant = vm.envOr("MERCHANT_ADDRESS", deployer);

        // Optional: policy config (USDC 6 decimals)
        uint256 maxPerTx = vm.envOr("MAX_PER_TX", uint256(20e6));
        uint256 dailyLimit = vm.envOr("DAILY_LIMIT", uint256(40e6));
        bool whitelist = vm.envOr("WHITELIST", true);

        // Optional: deposit config
        bool doDeposit = vm.envOr("DO_DEPOSIT", false);
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(200e6)); // 200 USDC

        // Optional: EIP-712 signature setup
        bool doPermits = vm.envOr("DO_PERMITS", true);
        uint256 ownerPk = vm.envOr("OWNER_PRIVATE_KEY", uint256(0));
        address owner = ownerPk == 0 ? address(0) : vm.addr(ownerPk);

        address expectedOwner = vm.envOr("OWNER_ADDRESS", address(0));
        if (expectedOwner != address(0)) {
            require(ownerPk != 0, "OWNER_PRIVATE_KEY required when OWNER_ADDRESS is set");
            require(owner == expectedOwner, "OWNER_PRIVATE_KEY does not match OWNER_ADDRESS");
        }

        // If no explicit owner provided, default to deployer (best for demos)
        if (owner == address(0)) {
            owner = deployer;
        }

        uint256 deadline = block.timestamp + 7 days;

        vm.startBroadcast(deployerPk);

        // 1) Deploy Vault pointing to real token (USDC Base Sepolia by default)
        ExpenseVault vault = new ExpenseVault(tokenAddr);

        // 2) Deploy simulated pool (same real token)
        SimulatedLiquidityPool pool = new SimulatedLiquidityPool(tokenAddr, annualRateBps);

        // 3) Deploy strategy (same real token)
        LiquidityPoolStrategy strategy = new LiquidityPoolStrategy(address(vault), tokenAddr, address(pool));

        // 4) Optional: owner deposits into the vault (requires owner == deployer in this script)
        //    For demo: run DO_DEPOSIT=true and make sure the deployer wallet has faucet USDC.
        if (doDeposit) {
            require(owner == deployer, "DO_DEPOSIT requires owner == deployer (same private key)");
            // Approve + deposit from deployer/owner
            IERC20(tokenAddr).approve(address(vault), depositAmount);
            vault.deposit(depositAmount);
        }

        // 5) Optional: Create policy and merchant allow via EIP-712 signatures (no mocks).
        //    Anyone can submit; we submit as deployer for simplicity.
        if (doPermits) {
            require(ownerPk != 0, "DO_PERMITS=true requires OWNER_PRIVATE_KEY");

            // a) SetPolicy signature
            uint256 nonce1 = vault.nonces(owner);

            bytes32 structHash1 = keccak256(
                abi.encode(
                    vault.SET_POLICY_TYPEHASH(),
                    owner,
                    spender,
                    true,
                    maxPerTx,
                    dailyLimit,
                    whitelist,
                    nonce1,
                    deadline
                )
            );

            bytes32 digest1 = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash1));
            (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPk, digest1);

            vault.setPolicyWithSig(
                owner,
                spender,
                true,
                maxPerTx,
                dailyLimit,
                whitelist,
                deadline,
                v1, r1, s1
            );

            // b) SetMerchantAllowed signature (only if whitelist=true)
            if (whitelist) {
                uint256 nonce2 = vault.nonces(owner);

                bytes32 structHash2 = keccak256(
                    abi.encode(
                        vault.SET_MERCHANT_TYPEHASH(),
                        owner,
                        spender,
                        merchant,
                        true,
                        nonce2,
                        deadline
                    )
                );

                bytes32 digest2 = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash2));
                (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ownerPk, digest2);

                vault.setMerchantAllowedWithSig(
                    owner,
                    spender,
                    merchant,
                    true,
                    deadline,
                    v2, r2, s2
                );
            }
        }

        vm.stopBroadcast();

        // --- Logs ---
        console2.log("Deployer:", deployer);
        console2.log("Owner:", owner);
        console2.log("Spender:", spender);
        console2.log("Merchant:", merchant);

        console2.log("Token (USDC):", tokenAddr);
        console2.log("ExpenseVault:", address(vault));
        console2.log("SimulatedLiquidityPool:", address(pool));
        console2.log("LiquidityPoolStrategy:", address(strategy));
    }
}


