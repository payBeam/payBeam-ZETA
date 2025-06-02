# PayBeam: Cross-Chain Split Payment System

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![ZetaChain](https://img.shields.io/badge/Powered%20by-ZetaChain-blueviolet)](https://zetachain.com)

PayBeam is a decentralized payment system built on ZetaChain's Universal contract framework, enabling merchants to create invoices that can be paid by multiple parties across different EVM-compatible blockchains. The system provides a seamless way to handle split payments and cross-chain transactions while maintaining robust security and transparency.

## Features

- 🌐 **Cross-Chain Payments**: Accept payments from any EVM-compatible blockchain
- 🔗 **Multi-Payer Support**: Multiple parties can contribute to a single invoice
- 📊 **Per-Chain Tracking**: Detailed tracking of payments by chain and payer
- 🔄 **Native & ZRC-20 Support**: Accept payments in both native ZETA and ZRC-20 tokens
- 🔐 **Relayer-Controlled**: Secure invoice creation and withdrawal management
- 📈 **Real-time Tracking**: Monitor payment status and chain contributions

## How It Works

1. **Invoice Hub**: PayBeamUniversal is deployed on ZetaChain's ZEVM, serving as the single "invoice hub"

2. **Cross-Chain Payments**:
   - Payers use their chain's ZetaChain GatewayEVM with `depositAndCall(...)`
   - ZetaChain protocol locks origin chain tokens and moves them to ZEVM
   - GatewayZEVM automatically calls `PayBeamUniversal.onCall(...)`
   - Payments recorded without needing a ZEVM wallet

3. **Escrow Management**:
   - All payments tracked per-chain and per-payer
   - Once fully funded, relayer calls `withdrawInvoice(...)`
   - Merchant receives full escrow in native ZETA or ZRC-20

4. **Seamless Integration**:
   - ZetaChain gateway handles token bridging automatically
   - Enables split payments across multiple chains
   - Maintains single source of truth on ZEVM

In summary: ZetaChain's infrastructure enables payers to contribute from any chain while maintaining a single invoice state on ZEVM.

## Architecture Overview

```
+-----------------+        +-----------------+        +-----------------+
|    Merchant     |        |    Payer 1     |        |    Payer 2     |
|    Backend      |        |    (Chain X)   |        |    (Chain Y)   |
+--------+--------+        +--------+-------+        +--------+-------+
         |                       |                       |
         |                       |                       |
         |                       |                       |
         v                       v                       v
+--------+--------+        +-----------------+        +-----------------+
| PayBeamConnected|        | PayBeamConnected|        | PayBeamConnected|
|    (Chain X)   |        |    (Chain Y)   |        |    (Chain Y)   |
+--------+--------+        +--------+-------+        +--------+-------+
         |                       |                       |
         |                       |                       |
         |                       |                       |
         v                       v                       v
+-----------------+        +-----------------+        +-----------------+
|    ZetaChain    |        |    ZetaChain    |        |    ZetaChain    |
|    Gateway      |        |    Gateway      |        |    Gateway      |
+--------+--------+        +--------+-------+        +--------+-------+
         |                       |                       |
         |                       |                       |
         |                       |                       |
         v                       v                       v
+-----------------+        +-----------------+        +-----------------+
|    PayBeamUniversal|        |    PayBeamUniversal|        |    PayBeamUniversal|
|    (ZEVM)        |        |    (ZEVM)        |        |    (ZEVM)        |
+-----------------+        +-----------------+        +-----------------+
         |                       |                       |
         |                       |                       |
         |                       |                       |
         v                       v                       v
+-----------------+        +-----------------+        +-----------------+
|    Merchant     |        |    Merchant     |        |    Merchant     |
|    Wallet       |        |    Wallet       |        |    Wallet       |
+-----------------+        +-----------------+        +-----------------+
```

## Cross-Chain Payment Flow

PayBeamUniversal is deployed on ZetaChain's ZEVM, making it the single "invoice hub." Here's how the cross-chain payment flow works:

1. **Origin Chain** (Any EVM-compatible chain):
   - Payers send funds (native or ZRC-20) via their chain's ZetaChain GatewayEVM using depositAndCall(...)
   - The ZetaChain protocol locks tokens on the origin chain

2. **ZetaChain Gateway**:
   - Automatically invokes PayBeamUniversal.onCall(...) on ZEVM
   - Passes along (invoiceId, payer) and the deposited amount

3. **ZEVM**:
   - PayBeamUniversal.onCall(...) records the payment without requiring a ZEVM wallet
   - Tracks per-payer and per-chain contributions
   - Emits PaymentReceived events

4. **Invoice Completion**:
   - Once total contributions meet or exceed invoice amount:
     - Marks invoice as "paid"
     - Emits InvoiceFullyPaid event
   - Relayer calls withdrawInvoice(...) to send escrow to merchant

Key Integration Points:
- **Gateway Integration**: Leverages ZetaChain's GatewayZEVM for cross-chain token transfers
- **Universal Contract**: Implements ZetaChain's UniversalContract interface for cross-chain calls
- **Token Handling**: Supports both native ZETA and ZRC-20 tokens across chains

This architecture enables seamless cross-chain split payments by:
- Leveraging ZetaChain's gateway for secure token bridging
- Maintaining a single source of truth on ZEVM
- Allowing payers to use their native chain wallets
- Providing real-time tracking of multi-chain contributions

## Prerequisites

- Solidity Compiler: ≥0.8.26
- Node.js: ≥16.0.0
- Hardhat: For local development
- ZetaChain Protocol Contracts:
  - @zetachain/protocol-contracts
  - GatewayZEVM
  - UniversalContract

## Installation


## Usage

### Merchant Backend

1. Create an invoice:
```javascript
const invoice = await payBeamUniversal.createInvoice(
  invoiceId,      // Unique identifier
  payoutToken,    // ZRC-20 address or address(0) for native ZETA
  amount,         // Total amount in smallest units
  description,    // Optional description
  merchantWallet, // Where funds will be sent
  merchantId      // Off-chain reference
);
```

2. Monitor payments:
```javascript
// Listen for PaymentReceived events
payBeamUniversal.on('PaymentReceived', (invoiceId, payer, token, amount) => {
  console.log(`Payment received for invoice ${invoiceId}`);
});
```

3. Withdraw funds:
```javascript
await payBeamUniversal.withdrawInvoice(invoiceId);
```

### Payer Interaction

1. Pay with native tokens:
```javascript
await payBeamConnected.payInvoiceCrossChain(
  invoiceId,
  chainId
).send({ value: amount });
```

2. Pay with ZRC-20 tokens:
```javascript
await payBeamConnected.payInvoiceWithTokenCrossChain(
  invoiceId,
  tokenAddress,
  amount,
  chainId
);
```

## Security Considerations

- All transactions are verified by the ZetaChain gateway
- Only authorized relayers can create invoices and withdraw funds
- Payments are tracked per-chain and per-payer for transparency
- Token approvals are required for ERC20 payments
- Revert options are configured for safe cross-chain transfers

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Support

For support, please open an issue in the repository

## Acknowledgments


## Future Enhancements

- Support for multiple token types (USDC, USDT, etc.)
- Invoice expiration handling
- Enhanced payment tracking and analytics
- Integration with popular wallet providers
- Mobile SDK support

## Documentation

- [PayBeam Technical Documentation](DOCUMENTATION.MD)
- [ZetaChain Universal Contracts Documentation](https://docs.zetachain.com/docs/develop/zeta-evm/universal-contracts)
- [ZetaChain Gateway Documentation](https://docs.zetachain.com/docs/develop/zeta-evm/gateway)
- [ZetaChain Cross-Chain Development Guide](https://docs.zetachain.com/docs/develop/zeta-evm/development-guide)

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Support

For support, please open an issue in the repository

## Acknowledgments

Built with ❤️ using ZetaChain's Universal Contract framework and Gateway technology.