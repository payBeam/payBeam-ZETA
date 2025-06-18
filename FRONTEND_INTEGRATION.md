# PayBeam Frontend Integration Guide

## Overview

This document explains how the frontend interacts with the PayBeam smart contracts. The system consists of two main contracts:

1. **PayBeamUniversal** (Deployed on ZetaChain Athens)
2. **PayBeamConnected** (Deployed on Base Sepolia and other EVM chains)

## Technical Architecture

### 1. PayBeamUniversal (ZetaChain)
- **Purpose**: Acts as the central hub for invoice management and fund distribution
- **Key Functions**:
  - `createInvoice()`: Creates a new payment request
  - `withdrawInvoice()`: Allows the merchant to withdraw funds
  - `onCall()`: Handles incoming cross-chain payments

### 2. PayBeamConnected (Base Sepolia)
- **Purpose**: Handles cross-chain token transfers from supported EVM chains
- **Key Functions**:
  - `payNativeCrossChain()`: For native token payments
  - `depositAndCall()`: For ERC20 token payments

## Frontend Integration

### Prerequisites
- Web3 provider (e.g., MetaMask, WalletConnect)
- Contract ABIs for both contracts
- ZetaChain RPC URL
- Base Sepolia RPC URL

### 1. Connecting to the Network

```javascript
// Connect to ZetaChain and Base Sepolia
const zetaProvider = new ethers.providers.JsonRpcProvider(ZETA_RPC_URL);
const baseProvider = new ethers.providers.Web3Provider(window.ethereum);
```

### 2. Contract Initialization

```javascript
// Initialize PayBeamUniversal (ZetaChain)
const payBeamUniversal = new ethers.Contract(
  PAYBEAM_UNIVERSAL_ADDRESS,
  PayBeamUniversalABI,
  zetaProvider
);

// Initialize PayBeamConnected (Base Sepolia)
const payBeamConnected = new ethers.Contract(
  PAYBEAM_CONNECTED_ADDRESS,
  PayBeamConnectedABI,
  baseProvider.getSigner()
);
```

### 3. Creating an Invoice (Merchant Flow)

```javascript
async function createInvoice(amount, tokenAddress, merchantWallet, description) {
  const invoiceId = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ['uint256', 'address', 'uint256'],
      [Date.now(), merchantWallet, Math.floor(Math.random() * 1000000)]
    )
  );

  const tx = await payBeamUniversal.createInvoice(
    invoiceId,
    amount,
    tokenAddress, // address(0) for native ZETA
    merchantWallet,
    description
  );
  
  await tx.wait();
  return invoiceId;
}
```

### 4. Making a Payment (User Flow)

#### For Native Tokens (e.g., ETH on Base Sepolia):

```javascript
async function payNative(invoiceId, amount) {
  const tx = await payBeamConnected.payNativeCrossChain(
    invoiceId,
    MERCHANT_ZETA_ADDRESS, // Merchant's ZetaChain address
    { value: amount }
  );
  
  await tx.wait();
}
```

#### For ERC20 Tokens:

```javascript
async function payWithERC20(invoiceId, tokenAddress, amount) {
  // Approve token spending first
  const token = new ethers.Contract(tokenAddress, ERC20_ABI, baseProvider.getSigner());
  await token.approve(PAYBEAM_CONNECTED_ADDRESS, amount);
  
  // Make payment
  const tx = await payBeamConnected.depositAndCall(
    invoiceId,
    MERCHANT_ZETA_ADDRESS,
    amount,
    tokenAddress,
    '0x', // Additional data if needed
    { gasLimit: 1000000 }
  );
  
  await tx.wait();
}
```

### 5. Withdrawing Funds (Merchant Flow)

```javascript
async function withdrawFunds(invoiceId) {
  const tx = await payBeamUniversal.withdrawInvoice(invoiceId);
  await tx.wait();
}
```

## User Experience Flow

### For Merchants:
1. Create an invoice using the merchant dashboard
2. Share the invoice ID with customers
3. Monitor payments in real-time
4. Withdraw funds when the invoice is fully paid

### For Customers:
1. Receive an invoice ID from the merchant
2. Connect their wallet to the payment page
3. Select payment method (native token or ERC20)
4. Confirm the transaction in their wallet
5. Receive confirmation of payment

## Error Handling

- Always check for transaction receipts
- Implement proper error boundaries
- Handle common errors like insufficient funds, wrong network, etc.
- Show user-friendly error messages

## Security Considerations

- Always verify contract addresses
- Use proper error handling for failed transactions
- Implement wallet connection state management
- Consider adding transaction confirmation modals
- Handle chain switching gracefully

## Testing

1. Test all flows on testnet first
2. Verify contract interactions using block explorers
3. Test with small amounts initially
4. Verify all events are emitted correctly

## Troubleshooting

- **Transaction Stuck**: Check gas prices and nonce
- **Wrong Network**: Prompt user to switch to the correct network
- **Insufficient Funds**: Show clear error message
- **Transaction Failed**: Parse the error message and provide guidance

## Additional Resources

- [ZetaChain Documentation](https://docs.zetachain.com/)
- [Ethers.js Documentation](https://docs.ethers.io/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)

---

*Note: Always refer to the latest contract ABIs and addresses from the official deployment.*
