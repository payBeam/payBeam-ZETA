#!/bin/bash

set -e
set -x
set -o pipefall

yarn zetachain localnet start --skip sui ton solana --exit-on-error &

while [ ! -f "localnet.json" ]; do sleep 1; done

npx hardhat compile --force --quiet


ZRC20_ETHEREUM=$(jq -r '.addresses[] | select(.type=="ZRC-20 ETH on 5") | .address' localnet.json)
ERC20_ETHEREUM=$(jq -r '.addresses[] | select(.type=="ERC-20 USDC" and .chain=="ethereum") | .address' localnet.json)
ZRC20_BNB=$(jq -r '.addresses[] | select(.type=="ZRC-20 BNB on 97") | .address' localnet.json)
# ZRC20_SOL=$(jq -r '.addresses[] | select(.type=="ZRC-20 SOL on 901") | .address' localnet.json)
ZRC20_SPL=$(jq -r '.addresses[] | select(.type=="ZRC-20 USDC on 901") | .address' localnet.json)
USDC_SPL=$(jq -r '.addresses[] | select(.type=="SPL-20 USDC") | .address' localnet.json)
GATEWAY_ETHEREUM=$(jq -r '.addresses[] | select(.type=="gatewayEVM" and .chain=="ethereum") | .address' localnet.json)
GATEWAY_ZETACHAIN=$(jq -r '.addresses[] | select(.type=="gatewayZEVM" and .chain=="zetachain") | .address' localnet.json)
SENDER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

CONTRACT_ZETACHAIN=$(npx hardhat deploy --name PayBeamUniversal --network localhost --gateway "$GATEWAY_ZETACHAIN" --json | jq -r '.contractAddress')
echo -e "\n🚀 Deployed contract on ZetaChain: $CONTRACT_ZETACHAIN"

CONTRACT_BASE=$(npx hardhat sdeploy --name PayBeamConnected --json --network localhost --gateway "$GATEWAY_ETHEREUM" | jq -r '.contractAddress')
echo -e "🚀 Deployed contract on Ethereum: $CONTRACT_BASE"

npx hardhat connected-deposit \
  --contract "$CONTRACT_BASE" \
  --receiver "$CONTRACT_ZETACHAIN" \
  --network localhost \
  --abort-address "$CONTRACT_ZETACHAIN" \
  --amount 1

  yarn zetachain localnet check

  