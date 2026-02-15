const IncidentRegistry = artifacts.require("IncidentRegistry");

// Already-deployed IdentityRegistry
// Shasta: TFKNqk9bjwWp5uRiiGimqfLhVQB8jSxYi7
// Mainnet: THmfi8uJuUpTfUmYLDX7UD1KaE4P6HKgqA
const IDENTITY_REGISTRY_ADDRESS = "THmfi8uJuUpTfUmYLDX7UD1KaE4P6HKgqA";

module.exports = async function(deployer, network, accounts) {
  console.log("\n========================================");
  console.log("Deploying IncidentRegistry (TRC-8004 v2 Extension)");
  console.log("Network:", network);
  console.log("Deployer:", accounts[0]);
  console.log("Using IdentityRegistry at:", IDENTITY_REGISTRY_ADDRESS);
  console.log("========================================\n");

  // Deploy IncidentRegistry (depends on IdentityRegistry)
  console.log("1. Deploying IncidentRegistry...");
  await deployer.deploy(IncidentRegistry, IDENTITY_REGISTRY_ADDRESS);
  const incidentRegistry = await IncidentRegistry.deployed();
  console.log("✅ IncidentRegistry deployed at:", incidentRegistry.address);

  // Summary
  console.log("\n========================================");
  console.log("DEPLOYMENT COMPLETE!");
  console.log("========================================");
  console.log("\nContract Address:");
  console.log("-------------------");
  console.log("IncidentRegistry:   ", incidentRegistry.address);

  console.log("\n📝 IMPORTANT: Add to your backend .env file:");
  console.log("\nINCIDENT_REGISTRY=" + incidentRegistry.address);
  console.log("\n========================================\n");
};
