const hre = require("hardhat");

async function main() {
  // Get the ContractFactory for TokenAuditTrail
  const TokenAuditTrail = await hre.ethers.getContractFactory(
    "TokenAuditTrail"
  );

  console.log("Deploying TokenAuditTrail contract...");

  // Deploy the contract
  const tokenAuditTrail = await TokenAuditTrail.deploy();

  await tokenAuditTrail.deployed();

  console.log("TokenAuditTrail deployed to:", tokenAuditTrail.address);
}

// Handle errors and run main
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
