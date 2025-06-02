# PayBeamUniversal: Cross-Chain Split-Payment System

A ZetaChain Universal Contract that enables merchants to create invoices and accept split payments from multiple payers across different EVM chains. Built on ZetaChain's cross-chain infrastructure, it leverages the Universal Contract framework and GatewayZEVM for seamless token transfers.

## Core Protocol Integration

### Contract Architecture
```solidity
contract PayBeamUniversal is UniversalContract {
    GatewayZEVM public immutable gateway;
    address public relayer;
    
    // Core mappings
    mapping(bytes32 => Invoice) public invoices;
    mapping(bytes32 => uint256) public escrow;
    mapping(bytes32 => mapping(address => uint256)) public payments;
    mapping(bytes32 => mapping(bytes32 => uint256)) public chainTotals;
}
```

### Key Integrations
- Implements `UniversalContract` interface for cross-chain calls
- Uses `GatewayZEVM` for token transfers between chains
- Maintains chain-agnostic escrow via ZetaChain's native token system

## Technical Flow

### Cross-Chain Payment Flow
1. **Invoice Creation**
   - Relayer calls `createInvoice(...)` on ZEVM
   - Invoice metadata stored in `invoices` mapping
   - Escrow initialized at zero

2. **Payment Processing**
   - Payers use `depositAndCall` on their chain's GatewayEVM
   - ZetaChain protocol locks origin chain tokens
   - GatewayZEVM invokes `onCall` with funds on ZEVM
   - PayBeamUniversal records payment via `_recordPayment`

3. **Escrow Management**
   - Native ZETA or ZRC-20 tokens stored in contract
   - Per-chain tracking via `chainTotals`
   - Per-payer tracking via `payments`
   - Global escrow via `escrow` mapping

4. **Withdrawal Flow**
   - Relayer calls `withdrawInvoice` when `totalReceived >= amount`
   - Contract transfers escrow to merchant
   - Emits `InvoiceWithdrawn` event

## Core Data Structures

### Invoice Struct
```solidity
struct Invoice {
    address payoutToken;      // ZRC-20 address or address(0) for native ZETA
    uint256 amount;           // Total due in smallest units
    address merchantWallet;   // Withdrawal destination
    bool paid;               // Payment status flag
    bool withdrawn;          // Withdrawal status flag
    uint256 totalReceived;   // Cumulative received amount
    uint256 timestamp;       // Invoice creation time
    string description;      // Optional metadata
}
```

### Payment Tracking
- `payments[invoiceId][payer]`: Per-payer contributions
- `chainTotals[invoiceId][chainId]`: Per-chain contributions
- `escrow[invoiceId]`: Total escrow amount

## Protocol-Specific Features

### Cross-Chain Integration
- Leverages ZetaChain's GatewayZEVM for token bridging
- Supports both native ZETA and ZRC-20 tokens
- Maintains chain-agnostic payment tracking
- Implements UniversalContract for cross-chain callbacks

### Security Features
- `onlyRelayer` modifier for invoice creation/withdrawal
- `onlyGateway` modifier for cross-chain callbacks
- Reentrancy protection in withdrawal flow
- Chain-specific payment validation

## Event Emission

### Core Events
```solidity
// Emitted when invoice is created
event InvoiceCreated(bytes32 invoiceId, address merchantId, address payoutToken, uint256 amount);

// Emitted when payment is received
event PaymentReceived(bytes32 invoiceId, address payer, address token, uint256 amount, uint256 totalEscrowed);

// Emitted when invoice is fully funded
event InvoiceFullyPaid(bytes32 invoiceId);

// Emitted when merchant withdraws funds
event InvoiceWithdrawn(bytes32 invoiceId, address merchantWallet, uint256 amount);
```

2. Prerequisites & Dependencies
Solidity Compiler: ≥0.8.26

ZetaChain Protocol Contracts:

@zetachain/protocol-contracts/contracts/Revert.sol

@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol

@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol

ZetaChain Localnet / Testnet/ Mainnet Endpoints:

ZEVM (ZetaChain’s EVM) RPC URL (e.g., http://localhost:8545 for localnet).

Corresponding GatewayZEVM contract address on the target ZEVM.

Node.js & Hardhat (optional): For local deployment and testing.

ERC-20 / ZRC-20 Token Interfaces: IZRC20 interface from ZetaChain contracts, for ZRC-20 transfers.

## Contract Structure & Data Model

### Core Contract Structure
```solidity
contract PayBeamUniversal is UniversalContract {
    GatewayZEVM public immutable gateway;
    address public relayer;

    struct Invoice {
        address payoutToken;      // ZRC-20 address or address(0) for native ZETA
        uint256 amount;           // total due (in smallest units)
        address merchantWallet;   // where funds go on withdraw
        address merchantId;       // off-chain reference (e.g. merchant's database ID)
        bool paid;                // true once totalReceived ≥ amount
        bool withdrawn;           // true once merchant has withdrawn funds
        uint256 totalReceived;    // cumulative funds received across all payers
        uint256 requiredAmount;   // identical to amount; kept for clarity
        uint256 timestamp;        // block.timestamp when invoice was created
        string description;       // optional human-readable description
    }

    // Primary Mappings
    mapping(bytes32 => Invoice) public invoices;
    mapping(bytes32 => uint256) public escrow;
    mapping(bytes32 => address[]) public payers;

    // Tracking Mappings
    mapping(bytes32 => mapping(address => uint256)) public payments;
    mapping(bytes32 => mapping(address => mapping(bytes32 => uint256))) public chainPayments;
    mapping(bytes32 => mapping(bytes32 => uint256)) public chainTotals;
    mapping(bytes32 => bytes32[]) public invoiceChains;
}
```	Type	Description
gateway	GatewayZEVM	ZetaChain Gateway contract on ZEVM. Used to send cross-chain calls.
relayer	address	Off-chain backend service (or EOA) that can create invoices and withdraw funds.
invoices	mapping(bytes32 => Invoice)	Stores each invoice’s metadata by invoiceId.
escrow	mapping(bytes32 => uint256)	Tracks cumulative funds held for each invoice.
payers	mapping(bytes32 => address[])	Array of payer addresses for each invoice.
payments	mapping(bytes32 => mapping(address => uint256))	Amount each payer has contributed to a given invoice.
chainPayments	mapping(bytes32 => mapping(address => mapping(bytes32 => uint256)))	How much each (invoiceId, payer, chainId) contributed.
chainTotals	mapping(bytes32 => mapping(bytes32 => uint256))	Total funds from each chainId for a given invoice.
invoiceChains	mapping(bytes32 => bytes32[])	List of distinct chainIds that have contributed to each invoice.

3.2 Invoice Struct
solidity
Copy
Edit
struct Invoice {
    address payoutToken;      // ZRC-20 or address(0) for native ZETA
    uint256 amount;           // total amount due
    address merchantWallet;   // where merchant ultimately receives funds
    address merchantId;       // off-chain reference (e.g. DB primary key or EOA)
    bool paid;                // flips true when totalReceived ≥ amount
    bool withdrawn;           // flips true when merchant has claimed funds
    uint256 totalReceived;    // cumulative amount of funds received so far
    uint256 requiredAmount;   // duplicate of amount, for clarity/tracking
    uint256 timestamp;        // block.timestamp at invoice creation
    string description;       // arbitrary invoice description (e.g. “Website design”)
}
payoutToken:

address(0) → native ZETA.

Nonzero → a ZRC-20 token address.

amount / requiredAmount: Target total (denominated in the smallest unit of payoutToken).

totalReceived: Sum of all deposits. Once totalReceived ≥ amount, paid = true.

timestamp: Helpful for auditing or invoice expiration logic (off-chain).

description: Human-friendly text.

## Core Functions & Workflows

### Modifiers & Errors
```solidity
modifier onlyRelayer() {
    if (msg.sender != relayer) revert Unauthorized();
    _;
}

modifier onlyGateway() {
    if (msg.sender != address(gateway)) revert Unauthorized();
    _;
}

error Unauthorized();
error InvoiceExists();
error NotFound();
error AlreadyWithdrawn();
error TransferFailed();
error NotFullyPaid();
```

- `onlyRelayer`: Restricts function calls to the backend relayer address (set in constructor)
- `onlyGateway`: Restricts onCall, onRevert, onAbort to only be invoked by the ZetaChain gateway
- Custom errors optimize gas and provide clear revert reasons

### Constructor & Relayer Management
```solidity
constructor(address payable gatewayAddress, address _relayer) {
    gateway = GatewayZEVM(gatewayAddress);
    relayer = _relayer;
}

function setRelayer(address _newRelayer) external onlyRelayer {
    relayer = _newRelayer;
}
```

#### Parameters
- `gatewayAddress`: Must be the deployed GatewayZEVM contract address on your ZEVM network
- `_relayer`: The off-chain service (or EOA) that manages invoice creation and withdrawals
- `setRelayer`: Allows the existing relayer to change to a new address for key rotation or backend upgrades

4.3 Invoice Creation
4.3.1 createInvoice(...)
solidity
Copy
Edit
function createInvoice(
    bytes32 invoiceId,
    address payoutToken,
    uint256 amount,
    string memory description,
    address merchantWallet,
    address merchantId
) external onlyRelayer {
    if (invoices[invoiceId].amount != 0) revert InvoiceExists();
    require(merchantWallet != address(0), "Zero merchant wallet");

    invoices[invoiceId] = Invoice({
        payoutToken:    payoutToken,
        amount:         amount,
        merchantWallet: merchantWallet,
        merchantId:     merchantId,
        paid:           false,
        withdrawn:      false,
        totalReceived:  0,
        requiredAmount: amount,
        timestamp:      block.timestamp,
        description:    description
    });

    emit InvoiceCreated(
        invoiceId,
        merchantId,
        payoutToken,
        amount,
        merchantWallet
    );
}
Access Control:

Only the relayer can call.

Invoice ID Uniqueness:

Reverts if invoices[invoiceId].amount != 0. That means you cannot use the same bytes32 twice.

Parameters:

invoiceId (bytes32): Unique identifier (e.g. keccak256(abi.encodePacked(“merchant123”, “order456”))).

payoutToken (address): address(0) for ZETA or ZRC-20 token address.

amount (uint256): Total due, in smallest units.

description (string): Optional human-readable description.

merchantWallet (address): Where to send funds on withdrawal.

merchantId (address): Off-chain reference (could be the merchant’s EOA or database ID encoded as an address).

Effects:

Stores a new Invoice struct.

Emits InvoiceCreated(invoiceId, merchantId, payoutToken, amount, merchantWallet).

4.3.2 callCreateInvoice(...) (Cross-Chain Invoice Creation)
solidity
Copy
Edit
function callCreateInvoice(
    bytes32 invoiceId,
    address payoutToken,
    uint256 amount,
    address merchantWallet,
    address merchantId,
    CallOptions memory callOptions,
    RevertOptions memory revertOptions,
    bytes memory receiver
) external onlyGateway {
    (address gasZRC20, uint256 gasFee) = IZRC20(payoutToken)
        .withdrawGasFeeWithGasLimit(callOptions.gasLimit);
    if (!IZRC20(payoutToken).transferFrom(msg.sender, address(this), gasFee)) {
        revert TransferFailed();
    }
    IZRC20(payoutToken).approve(address(gateway), gasFee);

    bytes memory message = abi.encode(
        invoiceId,
        payoutToken,
        amount,
        merchantWallet,
        merchantId
    );
    gateway.call(
        receiver,
        payoutToken,
        message,
        callOptions,
        revertOptions
    );
    emit InvoiceCallCreated(
        invoiceId,
        merchantId,
        payoutToken,
        amount,
        merchantWallet
    );
}
Purpose:

Allows a “Connected” contract on another chain to create an invoice on ZEVM via a cross-chain call.

The gateway invokes this function once it has received the gas fee in payoutToken.

Flow:

Compute gasZRC20 & gasFee via withdrawGasFeeWithGasLimit(callOptions.gasLimit).

Pull gasFee of payoutToken from msg.sender (which must be the gateway).

Approve the gateway to spend that gas fee.

Encode invoiceId, payoutToken, amount, merchantWallet, and merchantId into message.

Call gateway.call(...) to forward the call to the target contract (which might be a second hop if you’re chaining calls).

Emit InvoiceCallCreated(...) on ZEVM for off-chain indexing.

Note:

In many deployments, invoice creation is managed solely by the backend (calling createInvoice(...) directly). Use callCreateInvoice(...) only if merchants need to originate invoices from another chain directly (rather than your backend).

4.4 Payment Functions
Supports three modes of payment:

On-ZEVM native ZETA

On-ZEVM ZRC-20 token

Cross-Chain (any chain) → ZEVM via onCall

4.4.1 payInvoice(...) (Native ZETA on ZEVM)
solidity
Copy
Edit
function payInvoice(bytes32 invoiceId) external payable {
    _recordPayment(
        invoiceId,
        msg.sender,
        address(0),                // token = native ZETA
        msg.value,
        bytes32(uint256(7001))     // arbitrary ZEVM chain ID for same-chain payments
    );
}
Caller: Any EOA or contract on ZEVM, sending native ZETA.

Behavior:

msg.value ZETA arrives in this contract (via receive() or fallback()).

Calls internal _recordPayment(...) with:

token = address(0) to denote native.

chainId = bytes32(uint256(7001)). The value 7001 is an example chain ID representing ZEVM. Choose whichever numeric chain ID your ZEVM network uses; store it consistently off-chain for reporting.

Result:

Updates payments[invoiceId][payer], escrow[invoiceId], invoice.totalReceived, and chainTotals[invoiceId][chainId].

Emits PaymentReceived(...).

If threshold reached, emits InvoiceFullyPaid(...).

4.4.2 payInvoiceWithZRC20(...) (ZRC-20 on ZEVM)
solidity
Copy
Edit
function payInvoiceWithZRC20(
    bytes32 invoiceId,
    address zrc20,
    uint256 amount
) external {
    require(amount > 0, "Zero amount");
    require(zrc20 != address(0), "Zero token address");

    // Transfer ZRC-20 tokens into this contract
    IZRC20(zrc20).transferFrom(msg.sender, address(this), amount);
    IZRC20(zrc20).approve(address(gateway), amount);

    _recordPayment(
        invoiceId,
        msg.sender,
        zrc20,
        amount,
        bytes32(uint256(7001))
    );
}
Caller: Any EOA or contract on ZEVM—must have previously approve-ed this contract for at least amount of zrc20.

Behavior:

Pulls amount of ZRC-20 tokens from msg.sender.

Approves gateway for amount (so that cross-chain refunds/reverts, if invoked, can be handled).

Calls _recordPayment(...), using the same ZEVM chain ID as native.

Result:
function _recordPayment(
    bytes32 invoiceId,
    address payer,
    address token,
    uint256 amount,
    bytes32 chainId
) internal
```

### Requirements

* `invoiceId` must exist and not be paid.
* `payer` must not be the zero address.
* `token` must be a valid token address.
* `amount` must be greater than 0.
* `chainId` must be a valid chain ID.

### Behavior

1. Records the payment in the `chainPayments` mapping.
2. Updates the `chainTotals` mapping.
3. Adds the chain to the `invoiceChains` mapping if not already present.
4. Updates the general escrow and invoice tracking.
5. Emits the `PaymentReceived` event.
6. If the invoice is fully funded, emits the `InvoiceFullyPaid` event.

### Example
```solidity
// Record a payment for an invoice
_recordPayment(
    0x1234567890abcdef, // invoiceId
    0x1234567890abcdef, // payer
    0x0000000000000000000000000000000000000000, // token (native ZETA)
    100, // amount
    0x1234567890abcdef // chainId
);
```

## Events & Errors

### Events

| Event | Parameters | Description |
|-------|------------|-------------|
| InvoiceCreated | invoiceId, merchantId, payoutToken, amount, merchantWallet | Emitted when a new invoice is created |
| PaymentReceived | invoiceId, payer, token, amount, totalEscrowed | Emitted when a payment is received |
| InvoiceFullyPaid | invoiceId | Emitted when invoice is fully funded |
| InvoiceWithdrawn | invoiceId, merchantWallet, amount | Emitted when merchant withdraws funds |

### Errors

| Error | Scenario |
|-------|----------|
| Unauthorized | Caller is not relayer or gateway |
| InvoiceExists | Attempt to create an invoice with an existing ID |
| NotFound | Attempt to withdraw or reference a non-existent invoice |
| AlreadyWithdrawn | Attempt to withdraw an already withdrawn invoice |
| TransferFailed | Low-level transfer failed during withdrawal or payment |
| NotFullyPaid | Attempt to withdraw an invoice that is not fully funded |
Global Escrow & Invoice Metadata

escrow[invoiceId] += amount: Total funds held for invoice.

invoice.totalReceived += amount: Equivalent to escrow, but stored in the struct.

Per-Payer Tracking

If payments[invoiceId][payer] == 0, add payer to payers[invoiceId][].

payments[invoiceId][payer] += amount: Cumulative total by that payer.

Emit Event

PaymentReceived(invoiceId, payer, token, amount, escrow[invoiceId]).

If invoice.totalReceived ≥ invoice.amount, mark invoice.paid = true and emit InvoiceFullyPaid(invoiceId).

4.6 Withdrawal
solidity
Copy
Edit
function withdrawInvoice(bytes32 invoiceId) external onlyRelayer {
    Invoice storage inv = invoices[invoiceId];
    uint256 total = escrow[invoiceId];

    if (inv.amount == 0) revert NotFound();
    if (!inv.paid) revert NotFullyPaid();
    if (inv.withdrawn) revert AlreadyWithdrawn();
    if (total < inv.amount) revert NotFullyPaid();

    inv.withdrawn = true;

    // 1. Native ZETA payout
    if (inv.payoutToken == address(0)) {
        (bool ok, ) = inv.merchantWallet.call{ value: total }("");
        if (!ok) revert TransferFailed();
    } else {
        // 2. ZRC-20 token payout
        if (!IZRC20(inv.payoutToken).transfer(inv.merchantWallet, total)) {
            revert TransferFailed();
        }
    }

    emit InvoiceWithdrawn(invoiceId, inv.merchantWallet, total);
    delete escrow[invoiceId];
}
Logic Explained:

Access Control & Prechecks:

Only relayer can call.

Invoice must exist (inv.amount != 0).

Invoice must be marked paid = true.

Invoice must not have been withdrawn already (inv.withdrawn == false).

escrow[invoiceId] must be ≥ inv.amount.

Mark as Withdrawn

inv.withdrawn = true to prevent re-entrancy or double withdrawal.

Send Funds

If inv.payoutToken == address(0), send native ZETA via a low-level call. Revert if transfer fails.

Otherwise, call IZRC20(inv.payoutToken).transfer(...) to send ZRC-20 tokens to inv.merchantWallet. Revert if transfer fails.

Emit Event

InvoiceWithdrawn(invoiceId, merchantWallet, total).

Cleanup

delete escrow[invoiceId] resets the escrow for that invoice. (Invoice struct still remains for historical reference but escrow is now zero.)

4.7 Revert & Abort Callbacks
solidity
Copy
Edit
function onRevert(RevertContext calldata context) external onlyGateway {
    emit RevertEvent("Revert on ZetaChain", context);
}

function onAbort(AbortContext calldata context) external onlyGateway {
    emit AbortEvent("Abort on ZetaChain", context);
}
onRevert: Called by ZetaChain if a cross-chain call to this contract reverts on the destination chain. Emits RevertEvent with the RevertContext.

onAbort: Called if a cross-chain message is aborted (e.g. gas exhaustion). Emits AbortEvent.

Off-chain watchers can listen for these events to debug failed cross-chain flows.

4.8 Fallback & Receive
solidity
Copy
Edit
receive() external payable {}
fallback() external payable {}
These allow the contract to accept any incoming native ZETA, whether from direct transfers or from the cross-chain gateway moving funds.

5. Events & Errors
5.1 Events
Event	Parameters	Description
InvoiceCreated(bytes32 invoiceId, address merchantId, address payoutToken, uint256 amount, address merchantWallet)	- invoiceId: Unique invoice ID
- merchantId: Off-chain reference
- payoutToken: Token or 0x0
- amount: Amount due
- merchantWallet: Withdrawal address	Emitted when a new invoice is created on ZEVM (via createInvoice).
InvoiceCallCreated(bytes32 invoiceId, address merchantId, address payoutToken, uint256 amount, address merchantWallet)	Same as above. Emitted when an invoice is created via a cross-chain call (callCreateInvoice).	
PaymentReceived(bytes32 invoiceId, address payer, address token, uint256 amount, uint256 totalEscrowed)	- invoiceId
- payer: Address that paid
- token: Token address (0x0 for native)
- amount: Amount paid
- totalEscrowed: New total escrow for invoice	Emitted whenever any payment arrives (native, ZRC-20, cross-chain).
InvoiceFullyPaid(bytes32 invoiceId)	- invoiceId	Emitted once per invoice—when totalReceived ≥ amount.
InvoiceWithdrawn(bytes32 invoiceId, address merchantWallet, uint256 amount)	- invoiceId
- merchantWallet: Where funds were sent
- amount: Amount withdrawn (escrow)	Emitted after the merchant withdraws the full escrow.
RevertEvent(string message, RevertContext context)	- message: Human-readable (“Revert on ZetaChain”).
- context: Details of the revert.	Emitted when a cross-chain call to this contract reverts on the destination chain.
AbortEvent(string message, AbortContext context)	- message: Human-readable (“Abort on ZetaChain”).
- context: Details of the abort.	Emitted when a cross-chain call to this contract is aborted (e.g. out of gas).

5.2 Errors
Error	Scenario
Unauthorized()	Caller is not relayer (for createInvoice, withdrawInvoice) or not gateway (for onCall, onRevert).
InvoiceExists()	Attempt to create an invoice with a bytes32 invoiceId that already exists.
NotFound()	Attempt to withdraw or reference an invoice that does not exist (amount == 0).
AlreadyWithdrawn()	Attempt to withdraw an invoice that was already withdrawn.
TransferFailed()	Low-level transfer (native or ZRC-20) failed during withdrawal or callCreateInvoice fee transfer.
NotFullyPaid()	Attempt to withdraw an invoice that is not marked paid.

6. Cross-Chain Payment Flow
Below is a step-by-step explanation of how a payer on an external EVM chain (e.g. BSC, Avalanche, Ethereum) can pay a ZEVM invoice:

Backend Creates Invoice on ZEVM

Relayer calls createInvoice(invoiceId, payoutToken, amount, description, merchantWallet, merchantId) on ZEVM.

Off-chain watchers index InvoiceCreated.

Payer Interacts with “Connected” Contract (on External Chain)
A minimal “Connected” contract example (see next section) is deployed on each supported chain. Payers call one of its methods, which does:

If paying native (e.g. BNB on BSC):

solidity
Copy
Edit
function payInvoiceWithNative(bytes32 invoiceId, address payerOnZEVM) external payable {
    bytes memory data = abi.encode(invoiceId, payerOnZEVM);
    gateway.depositAndCall{ value: msg.value }(
        abi.encodePacked(payBeamUniversalZEVM), // ZEVM PayBeam address
        data,
        RevertOptions({ /* gasLimit, gasPrice, etc. */ })
    );
}
If paying ERC-20 (e.g. USDC on BSC):

solidity
Copy
Edit
function payInvoiceWithERC20(
    bytes32 invoiceId,
    address erc20,
    uint256 amount,
    address payerOnZEVM
) external {
    IERC20(erc20).transferFrom(msg.sender, address(this), amount);
    IERC20(erc20).approve(address(gateway), amount);
    bytes memory data = abi.encode(invoiceId, payerOnZEVM);
    gateway.depositAndCall(
        abi.encodePacked(payBeamUniversalZEVM),
        amount,
        erc20,
        data,
        RevertOptions({ /* gasLimit, gasPrice, etc. */ })
    );
}
Gateway Locks Funds & Routes to ZEVM

On the origin chain, GatewayEVM.depositAndCall(...) locks the tokens (or native) and emits an event.

ZetaChain’s cross-chain protocol moves equivalent ZRC-20 or native ZETA into PayBeamUniversal on ZEVM.

Once the funds arrive on ZEVM, the gateway calls PayBeamUniversal.onCall(ctx, zrc20, amount, message).

onCall Processes Payment on ZEVM

solidity
Copy
Edit
function onCall(
    MessageContext calldata ctx,
    address zrc20,
    uint256 amount,
    bytes calldata message
) external override onlyGateway {
    (bytes32 invoiceId, address payer) = abi.decode(message, (bytes32, address));
    _recordPayment(invoiceId, payer, zrc20, amount, bytes32(ctx.chainID));
}
Decodes (invoiceId, payer).

Updates per-payer, per-chain, and total escrow via _recordPayment.

Emits PaymentReceived. If totalReceived ≥ amount, emits InvoiceFullyPaid.

Relayer Monitors Events & Withdraws

Off-chain relayer listens for PaymentReceived and InvoiceFullyPaid via standard ZEVM RPC.

As soon as InvoiceFullyPaid(invoiceId) is emitted, relayer triggers withdrawInvoice(invoiceId) on ZEVM.

withdrawInvoice(...) sends native ZETA or ZRC-20 to merchantWallet.

Emits InvoiceWithdrawn.

7. Example “Connected” Contract
Place this contract on each external chain (e.g. BSC, Ethereum, Avalanche) so that payers can deposit funds cross-chain.

solidity
Copy
Edit
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@zetachain/protocol-contracts/contracts/evm/GatewayEVM.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PayBeamConnected {
    GatewayEVM public immutable gateway;
    address public payBeamUniversalZEVM; // PayBeamUniversal address on ZEVM

    constructor(address payable _gateway, address _universal) {
        gateway = GatewayEVM(_gateway);
        payBeamUniversalZEVM = _universal;
    }

    /// Pay with native currency (e.g. BNB on BSC)
    function payInvoiceWithNative(
        bytes32 invoiceId,
        address payerOnZEVM
    ) external payable {
        require(msg.value > 0, "No native sent");
        bytes memory data = abi.encode(invoiceId, payerOnZEVM);

        gateway.depositAndCall{ value: msg.value }(
            abi.encodePacked(payBeamUniversalZEVM),
            data,
            RevertOptions({ gasLimit: 200_000, zetaGasPrice: 1, zetaGasLimit: 2_000_000, zetaValue: 0 })
            // Adjust RevertOptions according to your network’s requirements
        );
    }

    /// Pay with ERC-20 token (e.g. USDC)
    function payInvoiceWithERC20(
        bytes32 invoiceId,
        address erc20,
        uint256 amount,
        address payerOnZEVM
    ) external {
        require(amount > 0, "Zero amount");
        IERC20(erc20).transferFrom(msg.sender, address(this), amount);
        IERC20(erc20).approve(address(gateway), amount);

        bytes memory data = abi.encode(invoiceId, payerOnZEVM);

        gateway.depositAndCall(
            abi.encodePacked(payBeamUniversalZEVM),
            amount,
            erc20,
            data,
            RevertOptions({ gasLimit: 200_000, zetaGasPrice: 1, zetaGasLimit: 2_000_000, zetaValue: 0 })
        );
    }

    /// Callback stubs (not strictly needed unless you want to handle reverts/returns)
    function onRevert(RevertContext calldata context) external onlyGateway {
        // Optionally handle aborted/reverted calls
    }

    function onCall(MessageContext calldata ctx, bytes calldata data) external onlyGateway returns (bytes4) {
        // Not used here, but must exist to satisfy interface if gateway targets this contract
        return bytes4(0);
    }

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert("Unauthorized");
        _;
    }

    receive() external payable {}
    fallback() external payable {}
}
Constructor Arguments:

_gateway: Address of GatewayEVM on this chain.

_universal: Address of PayBeamUniversal on ZEVM (encoded as raw bytes for the cross-chain call).

payInvoiceWithNative:

Caller sends native currency (BNB/ETH).

Encodes (invoiceId, payerOnZEVM) and invokes gateway.depositAndCall(...).

payInvoiceWithERC20:

Caller sends ERC-20 tokens.

Transfers tokens into this contract and approves the gateway.

Calls gateway.depositAndCall(...) with (invoiceId, payerOnZEVM).

Callbacks: If desired, implement onRevert(...) or onCall(...) to handle cross-chain reverts back to this chain.

8. Deployment & Integration Guide
8.1 Deploy on ZEVM (ZetaChain Localnet / Testnet / Mainnet)
Set Up Hardhat

bash
Copy
Edit
mkdir paybeam && cd paybeam
npm init -y
npm install --save-dev hardhat @zetachain/protocol-contracts
npx hardhat
# Choose “Create an empty hardhat.config.js”
Configure ZEVM Network in hardhat.config.js (example for local):

js
Copy
Edit
require("@nomiclabs/hardhat-ethers");
module.exports = {
  solidity: "0.8.26",
  networks: {
    zetachainlocal: {
      url: "http://127.0.0.1:8545",     // ZEVM localnet RPC
      chainId: 7001                     // Example ZEVM chain ID
    },
    // Add testnet/mainnet if available
  }
};
Write Deployment Script (scripts/deploy.js):

js
Copy
Edit
async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying as:", deployer.address);

  const GatewayAddress = "<ZEVM_GATEWAY_CONTRACT_ADDRESS>";
  const RelayerAddress = "<YOUR_RELAYER_EOA>";

  const PayBeam = await ethers.getContractFactory("PayBeamUniversal");
  const payBeam = await PayBeam.deploy(GatewayAddress, RelayerAddress);
  await payBeam.deployed();
  console.log("PayBeamUniversal deployed to:", payBeam.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
Deploy:

bash
Copy
Edit
npx hardhat run --network zetachainlocal scripts/deploy.js
Verify: Listen for InvoiceCreated or call invoices[abc] via a script or Hardhat console.

8.2 Deploy Connected Contract on External Chains
Set Up Hardhat or Remix on your target chain (BSC, Ethereum).

Configure that chain’s GatewayEVM address. (ZetaChain docs provide these addresses for each chain.)

Deploy PayBeamConnected, passing the chain’s GatewayEVM address and the PayBeamUniversal address on ZEVM.

js
Copy
Edit
const [deployer] = await ethers.getSigners();
const GatewayEVMAddress = "<BSC_GATEWAY_ADDRESS>";
const PayBeamZEVMAddress = "<0x...PayBeamUniversalOnZEVM>";
const PayBeamConn = await ethers.getContractFactory("PayBeamConnected");
const payBeamConn = await PayBeamConn.deploy(GatewayEVMAddress, PayBeamZEVMAddress);
await payBeamConn.deployed();
console.log("Connected contract on BSC deployed at:", payBeamConn.address);
8.3 Off-Chain Relayer Responsibilities
Invoice Generation:

Generate a unique bytes32 invoiceId (e.g. keccak256(…)).

Call createInvoice(invoiceId, payoutToken, amount, description, merchantWallet, merchantId) on ZEVM.

Monitoring Payments:

Subscribe to ZEVM events:

PaymentReceived(invoiceId, payer, token, amount, totalEscrowed)

InvoiceFullyPaid(invoiceId)

Whenever PaymentReceived fires, update your off-chain database to show which payer paid how much (and on which chain, by querying chainTotals[invoiceId][chainId]).

When InvoiceFullyPaid fires, mark the invoice as “funded” in your backend and notify the merchant—then trigger withdrawInvoice(invoiceId).

Withdrawal:

Call withdrawInvoice(invoiceId) on ZEVM.

Listen for InvoiceWithdrawn(invoiceId, merchantWallet, amount) to confirm the payout.

9. Typical Usage Example
Merchant signs up on your platform. Your backend stores merchant info (e.g. email, name, merchantId).

Backend (Relayer)

Generates new invoiceId = keccak256(abi.encodePacked(merchantId, orderNumber, timestamp)).

Chooses payoutToken (e.g. ZETA or ZRC-20).

Calls createInvoice(invoiceId, payoutToken, amount, description, merchantWallet, merchantId) on ZEVM.

Frontend or API displays invoice details (including the ZEVM contract address and invoiceId).

Payers

Navigate to invoice page (e.g. https://yourdapp.com/invoice/<invoiceId>).

See payment options:

“Pay with native (ZEVM ZETA)”

“Pay with ZRC-20 on ZEVM”

“Pay with [BSC native, BSC ERC-20, Ethereum, etc.]”

Select chain & method. If “Pay with BSC native”:

Frontend calls PayBeamConnected.payInvoiceWithNative(invoiceId, payerOnZEVMAddress) sending BNB.

This triggers the cross-chain flow described above.

ZEVM

onCall(...) receives funds, calls _recordPayment(...).

Emits PaymentReceived. If totalReceived ≥ amount, emits InvoiceFullyPaid.

Relayer sees InvoiceFullyPaid, calls withdrawInvoice(invoiceId).

Funds flow to merchantWallet.

InvoiceWithdrawn event emitted.

Merchant is notified off-chain that payment completed.

10. Security Considerations & Best Practices
InvoiceID Uniqueness: Generate non-colliding bytes32 IDs off-chain (e.g. hashing user + order + nonce).

Relayer Key Security:

Keep the relayer private key in a secure vault.

Use multi-sig if possible, or separate permissions (invoice creation vs. withdrawal).

Escrow Accuracy:

_recordPayment increments both escrow[invoiceId] and invoice.totalReceived. They should remain in sync.

If you add support for partial refunds (e.g. a payer disputes), add a matching “refund” function that subtracts from both.

Reentrancy:

withdrawInvoice sends funds via call. Marking inv.withdrawn = true before the external call prevents reentrancy on that invoice.

Cross-Chain Slippage:

ZetaChain’s gateway automatically handles gas fee conversion. Nonetheless, off-chain monitoring should confirm the exact amount received vs. expected.

Invoice Stale:

Consider adding an expiry timestamp off-chain. If an invoice is not paid within a timeframe, you can mark it invalid (no on-chain revert needed, just don’t let relayer withdraw).

Multiple Token Support:

If you want to allow payers to contribute in different tokens (e.g. invoice in USDC but payers send USDT → convert off-chain), you’d need a swap mechanism. Current design assumes “everyone pays in the same payoutToken.”

11. FAQ & Troubleshooting
Q: Why does chainId use bytes32(uint256(...))?
A: ZetaChain’s ctx.chainID is a uint256. We cast it to bytes32 so we can use it as a mapping key. If your chain ID is 7001, then bytes32(uint256(7001)) equals 0x…001B59. Store that same value off-chain to know which chain each payment came from.

Q: How do I know which chains contributed to an invoice?
A: Read invoiceChains[invoiceId][] to see a list of bytes32 chain IDs (e.g. 0x…001B59). Then use chainTotals[invoiceId][chainId] to get the total from each chain.

Q: A payer on ZEVM tries payInvoice but the invoice expects ZRC-20.
A: If payoutToken != address(0), reject native payments. The caller should use payInvoiceWithZRC20. You could add an explicit require(invoices[invoiceId].payoutToken == address(0)) in payInvoice to enforce this.

Q: Why do we call IZRC20(zrc20).approve(address(gateway), amount) in payInvoiceWithZRC20?
A: This is to allow the ZetaChain Gateway to perform refunds or reverts if the cross-chain call fails. If you never expect reverts, you can omit the approval, but it’s recommended for safety.

Q: How do I handle token decimals?
A: When creating an invoice in ZRC-20, use the token’s smallest unit (e.g. if USDC has 6 decimals, invoice amount = 10 * 10^6). Frontend should display amount / 10^decimals for human readability.

Q: Does callCreateInvoice actually store the invoice on ZEVM?
A: No, callCreateInvoice only re-emits the same parameters into a second cross-chain call. In most setups, you’ll skip callCreateInvoice and use createInvoice(...) directly.

12. Conclusion
With PayBeamUniversal, you can issue a single invoice on ZetaChain and accept contributions from payers on any connected EVM chain—native or ZRC-20—without requiring payers to hold a wallet on ZEVM. A backend relayer handles invoice creation, monitors payments, and executes withdrawals.

By following this README, you should be able to:

Deploy PayBeamUniversal on ZEVM.

Deploy PayBeamConnected on each external chain you wish to support.

Integrate your backend to create invoices, track events, and withdraw funds.

Build a frontend or API that displays invoice status in real time, including a breakdown by chain and payer.

