const ValidationRegistry = artifacts.require("ValidationRegistry");
const ReputationRegistry = artifacts.require("ReputationRegistry");

// PUT YOUR ALREADY-DEPLOYED IDENTITY REGISTRY ADDRESS HERE
const IDENTITY_REGISTRY_ADDRESS = "TFKNqk9bjwWp5uRiiGimqfLhVQB8jSxYi7";

module.exports = async function(deployer, network, accounts) {
  console.log("\n========================================");
  console.log("Deploying remaining M2M contracts");
  console.log("Network:", network);
  console.log("Deployer:", accounts[0]);
  console.log("Using IdentityRegistry at:", IDENTITY_REGISTRY_ADDRESS);
  console.log("========================================\n");

  // Deploy ValidationRegistry (depends on IdentityRegistry)
  console.log("1. Deploying ValidationRegistry...");
  await deployer.deploy(ValidationRegistry, IDENTITY_REGISTRY_ADDRESS);
  const validationRegistry = await ValidationRegistry.deployed();
  console.log("✅ ValidationRegistry deployed at:", validationRegistry.address);

  // Deploy ReputationRegistry (depends on IdentityRegistry)
  console.log("\n2. Deploying ReputationRegistry...");
  await deployer.deploy(ReputationRegistry, IDENTITY_REGISTRY_ADDRESS);
  const reputationRegistry = await ReputationRegistry.deployed();
  console.log("✅ ReputationRegistry deployed at:", reputationRegistry.address);

  // Summary
  console.log("\n========================================");
  console.log("DEPLOYMENT COMPLETE!");
  console.log("========================================");
  console.log("\nContract Addresses:");
  console.log("-------------------");
  console.log("IdentityRegistry:   ", IDENTITY_REGISTRY_ADDRESS);
  console.log("ValidationRegistry: ", validationRegistry.address);
  console.log("ReputationRegistry: ", reputationRegistry.address);

  console.log("\n📝 IMPORTANT: Save these addresses!");
  console.log("\nIDENTITY_REGISTRY=" + IDENTITY_REGISTRY_ADDRESS);
  console.log("VALIDATION_REGISTRY=" + validationRegistry.address);
  console.log("REPUTATION_REGISTRY=" + reputationRegistry.address);
  console.log("\n========================================\n");
};
