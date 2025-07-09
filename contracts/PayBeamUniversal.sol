// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RevertContext, RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";

// To be deployed to Zeta Athens
contract PayBeamUniversal is UniversalContract {
    GatewayZEVM public immutable gateway; // ZetaChain Gateway contract
    address public relayer; // Backend relayer address
    uint256 public gasLimit = 100000; 

    struct Invoice {
        address payoutToken; // ZRC-20 or address(0) for native ZETA
        uint256 amount; // total due
        address merchantWallet; // where funds go on withdraw
        string merchantId; // off-chain merchant reference
        bool paid; // reached threshold?
        bool withdrawn; // funds sent out?
        uint256 requiredAmount; // amount required to complete payment
        uint256 timestamp; // when invoice was created
        string description; // optional invoice description
        // Removed totalReceived; now tracked per token
    }

    mapping(bytes32 => Invoice) public invoices;
    // New: Track total received per invoice per token
    mapping(bytes32 => mapping(address => uint256)) public invoiceReceivedPerToken;
    mapping(bytes32 => uint256) public escrow; // total held
    mapping(bytes32 => address[]) public payers; // who’s paid

    mapping(string => uint256) public merchantBalance;
    
    // Track overpayments per payer
    mapping(bytes32 => mapping(address => uint256)) public overpayments;

    mapping(bytes32 => mapping(address => uint256)) public payments;
    mapping(bytes32 => mapping(address => mapping(bytes32 => uint256))) public chainPayments;
    // Track total amount paid per chain
    mapping(bytes32 => mapping(bytes32 => uint256)) public chainTotals;
    // Track which chains have been used for payment
    mapping(bytes32 => bytes32[]) public invoiceChains;

    // --- Events ---
    event InvoiceCreated(
        bytes32 indexed invoiceId,
        string indexed merchantId,
        address payoutToken,
        uint256 amount,
        address merchantWallet
    );
    event InvoiceCallCreated(
        bytes32 indexed invoiceId,
        string indexed merchantId,
        address payoutToken,
        uint256 amount,
        address merchantWallet
    );
    event PaymentReceived(
        bytes32 indexed invoiceId,
        address indexed payer,
        address token,
        uint256 amount,
        uint256 totalEscrowed
    );
    event InvoiceFullyPaid(bytes32 indexed invoiceId);
    event InvoiceWithdrawn(
        bytes32 indexed invoiceId,
        address indexed merchantWallet,
        uint256 amount
    );
    event RevertEvent(string, RevertContext);
    event AbortEvent(string, AbortContext);
    event OverpaymentDetected(
        bytes32 indexed invoiceId,
        address indexed payer,
        uint256 amount
    );
    event RefundProcessed(
        bytes32 indexed invoiceId,
        address indexed recipient,
        uint256 amount
    );
    event PingEvent(string indexed greeting, string message);
    event MerchantWalletUpdated(
        bytes32 indexed invoiceId,
        address newMerchantWallet
    );

    // --- Errors & Modifiers ---
    error Unauthorized();
    error InvoiceExists();
    error NotFound();
    error AlreadyWithdrawn();
    error TransferFailed();
    error NotFullyPaid();


    modifier onlyRelayer() {
        if (msg.sender != relayer) revert Unauthorized();
        _;
    }
    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    constructor(address payable gatewayAddress) {
        gateway = GatewayZEVM(gatewayAddress);
        relayer = address(0xC282Cb7cE6c175582B84BF94C61258Bb5cDCA88e);
    }

    function setRelayer(address _newRelayer) external onlyRelayer {
        relayer = _newRelayer;
    }

    /// @notice Backend-only: create a new invoice
    function createInvoice(
        bytes32 invoiceId,
        address payoutToken,
        uint256 amount,
        string memory description,
        address merchantWallet, // It can be address(0) for easy unboarding
        string memory merchantId
    ) external onlyRelayer {
        if (invoices[invoiceId].amount != 0) revert InvoiceExists();
        // require(merchantWallet != address(0), "Zero merchant wallet");

        invoices[invoiceId] = Invoice({
            payoutToken: payoutToken,
            amount: amount,
            merchantWallet: merchantWallet,
            merchantId: merchantId,
            paid: false,
            withdrawn: false,
            requiredAmount: amount,
            timestamp: block.timestamp,
            description: description
        });
        // No need to initialize invoiceReceivedPerToken here; will be set on payment
        emit InvoiceCreated(
            invoiceId,
            merchantId,
            payoutToken,
            amount,
            merchantWallet
        );
    }

    function setMerchantWallet(
        bytes32 invoiceId,
        address newMerchantWallet
    ) external onlyRelayer {
        Invoice storage invoice = invoices[invoiceId];
        require(invoice.amount != 0, "Invoice not found");
        require(newMerchantWallet != address(0), "Zero merchant wallet");

        invoice.merchantWallet = newMerchantWallet;
        emit MerchantWalletUpdated(invoiceId, newMerchantWallet);
    }

    function WithdrawCrossChain(
        bytes32 invoiceId,
        address payoutToken,
        uint256 amount,
        bytes memory receiver,
        // CallOptions memory callOptions,
        RevertOptions memory revertOptions
    ) external onlyGateway {
        (address gasZRC20, uint256 gasFee) = IZRC20(payoutToken)
            .withdrawGasFeeWithGasLimit(
                gasLimit 
            );
        if (
            !IZRC20(payoutToken).transferFrom(msg.sender, address(this), gasFee)
        ) revert TransferFailed();
        IZRC20(payoutToken).approve(address(gateway), gasFee);
        bytes memory message = abi.encode(
            invoiceId,
            payoutToken,
            amount,
            receiver
        );

        CallOptions memory callOptions = CallOptions(gasLimit, false);

        RevertOptions memory options = RevertOptions(
            address(this),
            true,
            address(0),
            message,
            gasLimit
        );

        gateway.call(
            receiver,
            payoutToken,
            message,
            callOptions,
            options
        );
    }
    
    

    function callCreateInvoice(
        bytes32 invoiceId,
        address payoutToken,
        uint256 amount,
        address merchantWallet,
        string memory merchantId,
        CallOptions memory callOptions,
        RevertOptions memory revertOptions,
        bytes memory receiver
    ) external onlyGateway {
        (address gasZRC20, uint256 gasFee) = IZRC20(payoutToken)
            .withdrawGasFeeWithGasLimit(
                callOptions.gasLimit //GatewayZEVM.GasLimit
            );
        if (
            !IZRC20(payoutToken).transferFrom(msg.sender, address(this), gasFee)
        ) {
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

    /// @notice Same-chain native ZETA deposit
    function payInvoice(bytes32 invoiceId) external payable {
        _recordPayment(
            invoiceId,
            msg.sender,
            address(0),
            msg.value,
            bytes32(uint256(7001))
        );
    }

    /// @notice Same-chain ZRC-20 deposit
    function payInvoiceWithZRC20(
        bytes32 invoiceId,
        address zrc20,
        uint256 amount
    ) external {
        require(amount > 0, "Zero amount");
        require(zrc20 != address(0), "Zero token address");

        // Transfer ZRC-20 tokens to this contract
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

    /// @notice Cross-chain deposit via ZetaChain Gateway
    /// @param ctx          Zeta-chain message context
    /// @param zrc20        token (address(0) for native)
    /// @param amount       amount received
    /// @param message      abi.encode(invoiceId, payer)
    function onCall(
        MessageContext calldata ctx,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override onlyGateway {
        (bytes32 invoiceId, address payer) = abi.decode(
            message,
            (bytes32, address)
        );
        _recordPayment(invoiceId, payer, zrc20, amount, bytes32(ctx.chainID));
    }

    /// @dev Records payment from a specific chain, marks paid when threshold met.
    /// @notice Get the total amount paid to an invoice
    /// @param invoiceId The ID of the invoice to check
    /// @return totalPaid The total amount paid to the invoice
    function getTotalPaid(bytes32 invoiceId, address token) external view returns (uint256 totalPaid) {
        return invoiceReceivedPerToken[invoiceId][token];
    }

    /// @notice Get the payment details for a specific payer on an invoice
    /// @param invoiceId The ID of the invoice
    /// @param payer The address of the payer to check
    /// @return amountPaid Total amount paid by this payer
    /// @return chains List of chain IDs where payments were made
    /// @return amounts List of amounts paid on each chain
    function getPayerPaymentDetails(
        bytes32 invoiceId,
        address payer
    ) external view returns (
        uint256 amountPaid,
        bytes32[] memory chains,
        uint256[] memory amounts
    ) {
        bytes32[] storage chainList = invoiceChains[invoiceId];
        uint256 chainCount = chainList.length;
        
        // Count how many chains have payments
        uint256 validChains = 0;
        for (uint256 i = 0; i < chainCount; i++) {
            if (chainPayments[invoiceId][payer][chainList[i]] > 0) {
                validChains++;
            }
        }
        
        // Initialize arrays
        chains = new bytes32[](validChains);
        amounts = new uint256[](validChains);
        
        // Fill arrays with payment data
        uint256 index = 0;
        for (uint256 i = 0; i < chainCount; i++) {
            bytes32 chainId = chainList[i];
            uint256 amount = chainPayments[invoiceId][payer][chainId];
            if (amount > 0) {
                chains[index] = chainId;
                amounts[index] = amount;
                amountPaid += amount;
                index++;
            }
        }
        
        return (amountPaid, chains, amounts);
    }

    /// @dev Process a refund for overpaid amounts
    /// @param invoiceId The ID of the invoice
    function claimRefund(bytes32 invoiceId) external {
        uint256 amount = overpayments[invoiceId][msg.sender];
        require(amount > 0, "No refund available");
        
        // Reset before transfer to prevent reentrancy
        overpayments[invoiceId][msg.sender] = 0;
        
        Invoice storage invoice = invoices[invoiceId];
        if (invoice.payoutToken == address(0)) {
            // Native token refund
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            // ZRC-20 token refund
            IZRC20(invoice.payoutToken).transfer(msg.sender, amount);
        }
        
        emit RefundProcessed(invoiceId, msg.sender, amount);
    }

    /// @dev Get the refundable amount for a specific payer and invoice
    /// @param invoiceId The ID of the invoice
    /// @param payer The address of the payer
    /// @return refundableAmount The amount that can be refunded
    function getRefundableAmount(
        bytes32 invoiceId, 
        address payer
    ) external view returns (uint256 refundableAmount) {
        return overpayments[invoiceId][payer];
    }

    function _recordPayment(
        bytes32 invoiceId,
        address payer,
        address token,
        uint256 amount,
        bytes32 chainId
    ) internal {
        Invoice storage invoice = invoices[invoiceId];
        require(!invoice.withdrawn, "Already withdrawn");

        // Track per-token received
        uint256 prevReceived = invoiceReceivedPerToken[invoiceId][token];
        uint256 required = invoice.requiredAmount;
        // Only check against requiredAmount if token matches payoutToken
        bool isPayoutToken = (token == invoice.payoutToken);
        uint256 remaining = isPayoutToken && prevReceived < required ? required - prevReceived : 0;
        uint256 appliedAmount = isPayoutToken ? (amount > remaining ? remaining : amount) : 0;
        
        // Update per-token received
        invoiceReceivedPerToken[invoiceId][token] += amount;

        // Handle overpayment for payoutToken
        if (isPayoutToken) {
            if (prevReceived < required) {
                // Only part of this payment may be overpayment
                if (amount > remaining) {
                    uint256 overpayment = amount - remaining;
                    overpayments[invoiceId][payer] += overpayment;
                    emit OverpaymentDetected(invoiceId, payer, overpayment);
                }
                // Mark as paid if fully covered
                if (invoiceReceivedPerToken[invoiceId][token] >= required) {
                    invoice.paid = true;
                    emit InvoiceFullyPaid(invoiceId);
                }
            } else {
                // Already fully paid, treat all as overpayment
                overpayments[invoiceId][payer] += amount;
                emit OverpaymentDetected(invoiceId, payer, amount);
            }
        }
        // Record the payment against the invoice
        _recordChainPayment(invoiceId, payer, amount, chainId, token);
    }
    
    /// @dev Internal function to record chain-specific payment details
    function _recordChainPayment(
        bytes32 invoiceId,
        address payer,
        uint256 amount,
        bytes32 chainId,
        address token
    ) internal {
        Invoice storage invoice = invoices[invoiceId];
        
        // Record chain-specific payment
        chainPayments[invoiceId][payer][chainId] += amount;
        chainTotals[invoiceId][chainId] += amount;

        // Add chain to invoice's chain list if not already present
        bytes32[] storage chains = invoiceChains[invoiceId];
        bool chainExists = false;
        
        // 
        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] == chainId) {
                chainExists = true;
                break;
            }
        }
        
        if (!chainExists) {
            chains.push(chainId);
        }

        // Update general escrow and invoice tracking
        escrow[invoiceId] += amount;
        
        // Add payer to the list if this is their first payment
        if (payments[invoiceId][payer] == 0) {
            payers[invoiceId].push(payer);
        }
        payments[invoiceId][payer] += amount;
        
        emit PaymentReceived(
            invoiceId,
            payer,
            token,
            amount,
            escrow[invoiceId]
        );
        
        // No need to check paid status here; handled in _recordPayment
    }

    /// @notice Backend-only: withdraw full escrow to merchant wallet
    function withdrawInvoice(bytes32 invoiceId) external onlyRelayer {
        Invoice storage invoice = invoices[invoiceId];
        uint256 total = invoiceReceivedPerToken[invoiceId][invoice.payoutToken];

        if (invoice.amount == 0) revert NotFound();
        if (!invoice.paid) revert NotFullyPaid();
        if (invoice.withdrawn) revert AlreadyWithdrawn();
        if (total < invoice.amount) revert NotFullyPaid();

        invoice.withdrawn = true;

        // send native ZETA
        if (invoice.payoutToken == address(0)) {
            (bool ok, ) = invoice.merchantWallet.call{value: total}("");
            if (!ok) revert TransferFailed();
        } else {
            // send ZRC-20 token
            if (!IZRC20(invoice.payoutToken).transfer(invoice.merchantWallet, total)) {
                revert TransferFailed();
            }
        }

        emit InvoiceWithdrawn(invoiceId, invoice.merchantWallet, total);

        // Only clear the payoutToken's received amount
        invoiceReceivedPerToken[invoiceId][invoice.payoutToken] = 0;
    }

    // --- Unused ZetaChain callbacks (stubs) ---
    function onRevert(RevertContext calldata context) external onlyGateway {
        emit RevertEvent("Revert on ZetaChain", context);
    }

    function onAbort(AbortContext calldata context) external onlyGateway {
        emit AbortEvent("Abort on ZetaChain", context);
    }

    receive() external payable {}

    fallback() external payable {}
}


