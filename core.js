// Core Blockchain Deployment Script for BitcoinYield-Pro
// Deploy smart contracts to Core blockchain testnet/mainnet

const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Core blockchain specific configurations
const CORE_CONFIG = {
  testnet: {
    chainId: 1115,
    rpcUrl: "https://rpc.test.btcs.network",
    explorerUrl: "https://scan.test.btcs.network",
    name: "Core Testnet"
  },
  mainnet: {
    chainId: 1116,
    rpcUrl: "https://rpc.coredao.org", 
    explorerUrl: "https://scan.coredao.org",
    name: "Core Mainnet"
  }
};

// Contract deployment configuration
const DEPLOYMENT_CONFIG = {
  // Core blockchain native tokens
  tokens: {
    testnet: {
      WBTC: "0x0000000000000000000000000000000000000000", // Will be deployed
      CORE: "0x0000000000000000000000000000000000000000"  // Native CORE token
    },
    mainnet: {
      WBTC: "0x0000000000000000000000000000000000000000", // Production WBTC
      CORE: "0x0000000000000000000000000000000000000000"  // Native CORE token
    }
  },
  
  // Core staking and bridge contracts (official Core addresses)
  coreContracts: {
    testnet: {
      staking: "0x0000000000000000000000000000000000001000", // Core staking contract
      bridge: "0x0000000000000000000000000000000000001001",  // BTC bridge contract
      validator: "0x0000000000000000000000000000000000001002"  // Default validator
    },
    mainnet: {
      staking: "0x0000000000000000000000000000000000001000",
      bridge: "0x0000000000000000000000000000000000001001", 
      validator: "0x0000000000000000000000000000000000001002"
    }
  }
};

async function main() {
  console.log("🚀 Starting Core Blockchain Deployment for BitcoinYield-Pro");
  console.log("=========================================================");

  // Get network info
  const network = await ethers.provider.getNetwork();
  const networkName = network.chainId === 1115 ? "testnet" : 
                      network.chainId === 1116 ? "mainnet" : "unknown";
  
  if (networkName === "unknown") {
    throw new Error(`Unsupported network. ChainId: ${network.chainId}`);
  }

  console.log(`📡 Network: ${CORE_CONFIG[networkName].name} (${network.chainId})`);
  
  // Get deployer account
  const [deployer] = await ethers.getSigners();
  const deployerBalance = await deployer.getBalance();
  
  console.log(`👤 Deployer: ${deployer.address}`);
  console.log(`💰 Balance: ${ethers.utils.formatEther(deployerBalance)} CORE`);
  
  if (deployerBalance.lt(ethers.utils.parseEther("0.1"))) {
    throw new Error("Insufficient CORE balance for deployment. Need at least 0.1 CORE");
  }

  const deploymentResults = {};
  
  try {
    // Step 1: Deploy Mock WBTC if needed (testnet only)
    if (networkName === "testnet") {
      console.log("\n📝 Step 1: Deploying Mock WBTC for testnet...");
      const MockWBTC = await ethers.getContractFactory("MockWBTC");
      const wbtc = await MockWBTC.deploy(
        "Wrapped Bitcoin",
        "WBTC",
        18,
        ethers.utils.parseEther("21000000") // 21M total supply
      );
      await wbtc.deployed();
      
      deploymentResults.WBTC = wbtc.address;
      console.log(`✅ Mock WBTC deployed to: ${wbtc.address}`);
    }

    // Step 2: Deploy Core Yield Vault
    console.log("\n📝 Step 2: Deploying CoreYieldVault...");
    
    const wbtcAddress = networkName === "testnet" ? 
      deploymentResults.WBTC : 
      DEPLOYMENT_CONFIG.tokens[networkName].WBTC;
    
    const coreTokenAddress = DEPLOYMENT_CONFIG.tokens[networkName].CORE;
    const coreStakingAddress = DEPLOYMENT_CONFIG.coreContracts[networkName].staking;
    const coreBridgeAddress = DEPLOYMENT_CONFIG.coreContracts[networkName].bridge;
    const validatorAddress = DEPLOYMENT_CONFIG.coreContracts[networkName].validator;

    const CoreYieldVault = await ethers.getContractFactory("CoreYieldVault");
    const vault = await CoreYieldVault.deploy(
      wbtcAddress,
      coreTokenAddress, 
      coreStakingAddress,
      coreBridgeAddress,
      validatorAddress,
      "BitcoinYield Pro Vault",
      "BYP-VAULT"
    );
    await vault.deployed();
    
    deploymentResults.CoreYieldVault = vault.address;
    console.log(`✅ CoreYieldVault deployed to: ${vault.address}`);

    // Step 3: Deploy Yield Strategy Contract
    console.log("\n📝 Step 3: Deploying YieldStrategy...");
    
    const YieldStrategy = await ethers.getContractFactory("CoreYieldStrategy");
    const strategy = await YieldStrategy.deploy(
      vault.address,
      coreStakingAddress,
      validatorAddress
    );
    await strategy.deployed();
    
    deploymentResults.YieldStrategy = strategy.address;
    console.log(`✅ YieldStrategy deployed to: ${strategy.address}`);

    // Step 4: Deploy Liquidity Pool Manager
    console.log("\n📝 Step 4: Deploying LiquidityPoolManager...");
    
    const LiquidityPoolManager = await ethers.getContractFactory("LiquidityPoolManager");
    const lpManager = await LiquidityPoolManager.deploy(
      wbtcAddress,
      coreTokenAddress,
      vault.address
    );
    await lpManager.deployed();
    
    deploymentResults.LiquidityPoolManager = lpManager.address;
    console.log(`✅ LiquidityPoolManager deployed to: ${lpManager.address}`);

    // Step 5: Configure contracts
    console.log("\n📝 Step 5: Configuring contracts...");
    
    // Set yield strategy in vault
    await vault.setYieldStrategy(strategy.address);
    console.log("✅ Yield strategy set in vault");
    
    // Set liquidity pool manager in vault  
    await vault.setLiquidityPool(lpManager.address);
    console.log("✅ Liquidity pool manager set in vault");

    // Step 6: Deploy Governance Token (optional)
    console.log("\n📝 Step 6: Deploying Governance Token...");
    
    const GovernanceToken = await ethers.getContractFactory("BYPGovernanceToken");
    const govToken = await GovernanceToken.deploy(
      "BitcoinYield Pro Governance",
      "BYP",
      ethers.utils.parseEther("1000000"), // 1M total supply
      deployer.address
    );
    await govToken.deployed();
    
    deploymentResults.GovernanceToken = govToken.address;
    console.log(`✅ Governance token deployed to: ${govToken.address}`);

    // Step 7: Deploy Timelock Controller for governance
    console.log("\n📝 Step 7: Deploying Timelock Controller...");
    
    const TimelockController = await ethers.getContractFactory("TimelockController");
    const timelock = await TimelockController.deploy(
      86400, // 1 day delay
      [deployer.address], // proposers
      [deployer.address], // executors  
      deployer.address    // admin
    );
    await timelock.deployed();
    
    deploymentResults.TimelockController = timelock.address;
    console.log(`✅ Timelock controller deployed to: ${timelock.address}`);

    // Step 8: Save deployment results
    console.log("\n📝 Step 8: Saving deployment results...");
    
    const deploymentData = {
      network: networkName,
      chainId: network.chainId,
      deploymentTime: new Date().toISOString(),
      deployer: deployer.address,
      contracts: deploymentResults,
      configuration: {
        fees: {
          managementFee: 150, // 1.5%
          performanceFee: 800, // 8%
          coreDelegationFee: 50 // 0.5%
        },
        ratios: {
          stakingRatio: 5000, // 50%
          liquidityRatio: 3000, // 30%  
          reserveRatio: 2000 // 20%
        },
        limits: {
          minDeposit: ethers.utils.parseEther("0.001").toString(),
          lockPeriod: 604800, // 7 days
          minCoreStaking: ethers.utils.parseEther("1").toString()
        }
      },
      verification: {
        explorerUrl: CORE_CONFIG[networkName].explorerUrl,
        contractUrls: Object.keys(deploymentResults).reduce((urls, contractName) => {
          urls[contractName] = `${CORE_CONFIG[networkName].explorerUrl}/address/${deploymentResults[contractName]}`;
          return urls;
        }, {})
      }
    };

    // Save to file
    const deploymentsDir = path.join(__dirname, "../deployments");
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    const filename = `${networkName}-deployment-${Date.now()}.json`;
    const filepath = path.join(deploymentsDir, filename);
    
    fs.writeFileSync(filepath, JSON.stringify(deploymentData, null, 2));
    
    // Also save as latest
    const latestFilepath = path.join(deploymentsDir, `${networkName}-latest.json`);
    fs.writeFileSync(latestFilepath, JSON.stringify(deploymentData, null, 2));

    console.log(`✅ Deployment data saved to: ${filename}`);

    // Step 9: Display summary
    console.log("\n🎉 Deployment Complete!");
    console.log("========================");
    
    console.log(`\n📊 Deployed Contracts on ${CORE_CONFIG[networkName].name}:`);
    Object.entries(deploymentResults).forEach(([name, address]) => {
      console.log(`   ${name}: ${address}`);
    });
    
    console.log(`\n🔗 Explorer URLs:`);
    Object.entries(deploymentResults).forEach(([name, address]) => {
      console.log(`   ${name}: ${CORE_CONFIG[networkName].explorerUrl}/address/${address}`);
    });
    
    console.log(`\n⚙️  Configuration:`);
    console.log(`   Management Fee: 1.5%`);
    console.log(`   Performance Fee: 8%`);
    console.log(`   Core Delegation Fee: 0.5%`);
    console.log(`   Staking Ratio: 50%`);
    console.log(`   Liquidity Ratio: 30%`);
    console.log(`   Reserve Ratio: 20%`);
    
    console.log(`\n🔧 Next Steps:`);
    console.log(`   1. Verify contracts on Core explorer`);
    console.log(`   2. Update frontend configuration with contract addresses`);
    console.log(`   3. Fund contracts with initial liquidity for testing`);
    console.log(`   4. Set up monitoring and alerts`);
    
    if (networkName === "testnet") {
      console.log(`\n🧪 Testnet specific:`);
      console.log(`   1. Get testnet CORE from faucet: https://scan.test.btcs.network/faucet`);
      console.log(`   2. Mint test WBTC from deployed mock contract`);
      console.log(`   3. Test all functions before mainnet deployment`);
    }

  } catch (error) {
    console.error("\n❌ Deployment failed:", error.message);
    
    // Save failed deployment info
    const failedDeploymentData = {
      network: networkName,
      deploymentTime: new Date().toISOString(),
      deployer: deployer.address,
      error: error.message,
      partialDeployments: deploymentResults
    };
    
    const deploymentsDir = path.join(__dirname, "../deployments");
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    const failedFilename = `${networkName}-failed-deployment-${Date.now()}.json`;
    const failedFilepath = path.join(deploymentsDir, failedFilename);
    
    fs.writeFileSync(failedFilepath, JSON.stringify(failedDeploymentData, null, 2));
    console.log(`💾 Failed deployment info saved to: ${failedFilename}`);
    
    process.exit(1);
  }
}

// Handle script execution
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("❌ Deployment script error:", error);
      process.exit(1);
    });
}

module.exports = { main, CORE_CONFIG, DEPLOYMENT_CONFIG };
	
