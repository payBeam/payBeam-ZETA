#!/bin/bash

set -e
set -x
set -o pipefail

# Start local ZetaChain network
echo "🚀 Starting local ZetaChain network..."
yarn zetachain localnet start --skip sui ton solana --exit-on-error &

# Wait for localnet.json to be created
while [ ! -f "localnet.json" ]; do sleep 1; done

# Compile contracts
echo "🔧 Compiling contracts..."
npx hardhat compile --force --quiet

# Load contract addresses from localnet.json
echo "📡 Loading contract addresses..."
ZRC20_ETHEREUM=$(jq -r '.addresses[] | select(.type=="ZRC-20 ETH on 5") | .address' localnet.json)
ERC20_ETHEREUM=$(jq -r '.addresses[] | select(.type=="ERC-20 USDC" and .chain=="ethereum") | .address' localnet.json)
ZRC20_BNB=$(jq -r '.addresses[] | select(.type=="ZRC-20 BNB on 97") | .address' localnet.json)
ZRC20_SPL=$(jq -r '.addresses[] | select(.type=="ZRC-20 USDC on 901") | .address' localnet.json)
USDC_SPL=$(jq -r '.addresses[] | select(.type=="SPL-20 USDC") | .address' localnet.json)
GATEWAY_ETHEREUM=$(jq -r '.addresses[] | select(.type=="gatewayEVM" and .chain=="ethereum") | .address' localnet.json)
GATEWAY_ZETACHAIN=$(jq -r '.addresses[] | select(.type=="gatewayZEVM" and .chain=="zetachain") | .address' localnet.json)

# Test accounts
SENDER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
MERCHANT_WALLET=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
MERCHANT_ID="merchant123"
MERCHANT_ID2="merchant456"
INVOICE_ID=$(cast keccak "$(date +%s)" | cut -c3-18) # bytes32 format

# Deploy contracts
echo "🚀 Deploying PayBeamUniversal to ZetaChain..."
CONTRACT_ZETACHAIN=$(npx hardhat deploy --name PayBeamUniversal --network localhost --gateway "$GATEWAY_ZETACHAIN" --json | jq -r '.contractAddress')
echo "✅ PayBeamUniversal deployed to: $CONTRACT_ZETACHAIN"

echo "🚀 Deploying PayBeamConnected to Ethereum..."
CONTRACT_ETHEREUM=$(npx hardhat sdeploy --name PayBeamConnected --json --network localhost --gateway "$GATEWAY_ETHEREUM" | jq -r '.contractAddress')
echo "✅ PayBeamConnected deployed to: $CONTRACT_ETHEREUM"

# Test 1: Create an invoice
echo "\n🔍 Test 1: Creating an invoice..."
npx hardhat --network localhost invoke $CONTRACT_ZETACHAIN \
  "createInvoice(bytes32,address,uint256,string,address,string)" \
  $INVOICE_ID \
  $ZRC20_ETHEREUM \
  1000000000000000000 \
  "Test invoice" \
  $MERCHANT_WALLET \
  $MERCHANT_ID

echo "✅ Invoice created with ID: $INVOICE_ID"

# Test 2: Make a payment
echo "\n💰 Test 2: Making a payment..."
npx hardhat connected-deposit \
  --contract "$CONTRACT_ETHEREUM" \
  --receiver "$CONTRACT_ZETACHAIN" \
  --network localhost \
  --abort-address "$CONTRACT_ZETACHAIN" \
  --amount 0.5

echo "✅ Payment made successfully"

# Test 3: Check invoice status
echo "\n📊 Test 3: Checking invoice status..."
npx hardhat --network localhost call $CONTRACT_ZETACHAIN \
  "getInvoice(bytes32)(address,uint256,address,string,bool,bool,uint256,uint256,uint256,string)" \
  $INVOICE_ID

echo "✅ Invoice status retrieved"

# Test 4: Make an overpayment
echo "\n💸 Test 4: Making an overpayment..."
npx hardhat connected-deposit \
  --contract "$CONTRACT_ETHEREUM" \
  --receiver "$CONTRACT_ZETACHAIN" \
  --network localhost \
  --abort-address "$CONTRACT_ZETACHAIN" \
  --amount 0.6

echo "✅ Overpayment made successfully"

# Test 5: Check overpayment amount
echo "\n📈 Test 5: Checking overpayment amount..."
npx hardhat --network localhost call $CONTRACT_ZETACHAIN \
  "getRefundableAmount(bytes32,address)(uint256)" \
  $INVOICE_ID \
  $SENDER

echo "✅ Overpayment amount checked"

# Test 6: Withdraw invoice (as relayer)
echo "\n🏧 Test 6: Withdrawing invoice..."
npx hardhat --network localhost invoke $CONTRACT_ZETACHAIN \
  "withdrawInvoice(bytes32)" \
  $INVOICE_ID

echo "✅ Invoice withdrawn successfully"

# Final check
echo "\n✅ All tests completed successfully!"
yarn zetachain localnet check