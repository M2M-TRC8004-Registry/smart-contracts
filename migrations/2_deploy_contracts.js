const EnhancedIdentityRegistry = artifacts.require("EnhancedIdentityRegistry");
const ValidationRegistry = artifacts.require("ValidationRegistry");
const ReputationRegistry = artifacts.require("ReputationRegistry");

module.exports = async function(deployer, network, accounts) {
  console.log("\n========================================");
  console.log("Deploying M2M TRC-8004 Agent Registry Contracts");
  console.log("Network:", network);
  console.log("Deployer:", accounts[0]);
  console.log("========================================\n");
  
  // Deploy IdentityRegistry (ERC-721 for agents)
  console.log("1. Deploying EnhancedIdentityRegistry...");
  await deployer.deploy(EnhancedIdentityRegistry, "M2M TRC-8004 Agent Registry", "M2MAGENT");
  const identityRegistry = await EnhancedIdentityRegistry.deployed();
  console.log("✅ EnhancedIdentityRegistry deployed at:", identityRegistry.address);
  
  // Deploy ValidationRegistry (depends on IdentityRegistry)
  console.log("\n2. Deploying ValidationRegistry...");
  await deployer.deploy(ValidationRegistry, identityRegistry.address);
  const validationRegistry = await ValidationRegistry.deployed();
  console.log("✅ ValidationRegistry deployed at:", validationRegistry.address);
  
  // Deploy ReputationRegistry (depends on IdentityRegistry)
  console.log("\n3. Deploying ReputationRegistry...");
  await deployer.deploy(ReputationRegistry, identityRegistry.address);
  const reputationRegistry = await ReputationRegistry.deployed();
  console.log("✅ ReputationRegistry deployed at:", reputationRegistry.address);
  
  // Summary
  console.log("\n========================================");
  console.log("DEPLOYMENT COMPLETE!");
  console.log("========================================");
  console.log("\nContract Addresses:");
  console.log("-------------------");
  console.log("IdentityRegistry:   ", identityRegistry.address);
  console.log("ValidationRegistry: ", validationRegistry.address);
  console.log("ReputationRegistry: ", reputationRegistry.address);
  
  console.log("\n📝 IMPORTANT: Save these addresses!");
  console.log("Add them to your backend .env file:");
  console.log("\nIDENTITY_REGISTRY=" + identityRegistry.address);
  console.log("VALIDATION_REGISTRY=" + validationRegistry.address);
  console.log("REPUTATION_REGISTRY=" + reputationRegistry.address);
  console.log("\n========================================\n");
};
