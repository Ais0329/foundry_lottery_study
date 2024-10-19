-include .env

.PHONY:build test all depoly-sepolia

build:
	forge build

test:
	forge test

depoly-sepolia:
	@forge script script/DeployRaffle.s.sol:DeployRaffle --rpc-url $(SEPOLIA_RPC_URL) --account SEPOLIA_myaccount --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv