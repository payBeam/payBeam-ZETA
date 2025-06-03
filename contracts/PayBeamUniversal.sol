// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RevertContext, RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";

contract PayBeamUniversal is UniversalContract {
    GatewayZEVM public immutable gateway; // ZetaChain Gateway contract
    address public relayer; // Backend relayer address

    struct Invoice {
        address payoutToken; // ZRC-20 or address(0) for native ZETA
        uint256 amount; // total due
        address merchantWallet; // where funds go on withdraw
        address merchantId; // off-chain merchant reference
        bool paid; // reached threshold?
        bool withdrawn; // funds sent out?
        uint256 totalReceived; // total amount received across all chains
        uint256 requiredAmount; // amount required to complete payment
        uint256 timestamp; // when invoice was created
        string description; // optional invoice description
    }

    mapping(bytes32 => Invoice) public invoices;
    mapping(bytes32 => uint256) public escrow; // total held
    mapping(bytes32 => address[]) public payers; // who’s paid

    mapping(bytes32 => mapping(address => uint256)) public payments;
    // Track tokens payed by payers per invoice
    // Track tokens paid by payers per invoice and chain
    mapping(bytes32 => mapping(address => mapping(bytes32 => uint256)))
        public chainPayments;
    // Track total amount paid per chain
    mapping(bytes32 => mapping(bytes32 => uint256)) public chainTotals;
    // Track which chains have been used for payment
    mapping(bytes32 => bytes32[]) public invoiceChains;

    // --- Events ---
    event InvoiceCreated(
        bytes32 indexed invoiceId,
        address indexed merchantId,
        address payoutToken,
        uint256 amount,
        address merchantWallet
    );
    event InvoiceCallCreated(
        bytes32 indexed invoiceId,
        address indexed merchantId,
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
        relayer = address(0x60eF148485C2a5119fa52CA13c52E9fd98F28e87);
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
        address merchantWallet,
        address merchantId
    ) external onlyRelayer {
        if (invoices[invoiceId].amount != 0) revert InvoiceExists();
        require(merchantWallet != address(0), "Zero merchant wallet");

        invoices[invoiceId] = Invoice({
            payoutToken: payoutToken,
            amount: amount,
            merchantWallet: merchantWallet,
            merchantId: merchantId,
            paid: false,
            withdrawn: false,
            totalReceived: 0,
            requiredAmount: amount,
            timestamp: block.timestamp,
            description: description
        });

        emit InvoiceCreated(
            invoiceId,
            merchantId,
            payoutToken,
            amount,
            merchantWallet
        );
    }

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
        _recordPayment(invoiceId, msg.sender, address(0), msg.value, bytes32(uint256(7001)));
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

        _recordPayment(invoiceId, msg.sender, zrc20, amount, bytes32(uint256(7001)));
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
    function _recordPayment(
        bytes32 invoiceId,
        address payer,
        address token,
        uint256 amount,
        bytes32 chainId
    ) internal {
        Invoice storage invoice = invoices[invoiceId];
        require(!invoice.paid, "Already paid");
        require(!invoice.withdrawn, "Already withdrawn");

        // Record chain-specific payment
        chainPayments[invoiceId][payer][chainId] += amount;
        chainTotals[invoiceId][chainId] += amount;

        // Add chain to invoice's chain list if not already present
        bytes32[] storage chains = invoiceChains[invoiceId];
        bool chainExists = false;
        for (uint i = 0; i < chains.length; i++) {
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
        invoice.totalReceived += amount;

        if (payments[invoiceId][payer] == 0) {
            payers[invoiceId].push(payer);
        }
        payments[invoiceId][payer] += amount;
        // tokens[invoiceId][token] += amount;

        emit PaymentReceived(
            invoiceId,
            payer,
            token,
            amount,
            escrow[invoiceId]
        );

        if (invoice.totalReceived >= invoice.amount) {
            invoice.paid = true;
            emit InvoiceFullyPaid(invoiceId);
        }
    }

    /// @notice Backend-only: withdraw full escrow to merchant wallet
    function withdrawInvoice(bytes32 invoiceId) external onlyRelayer {
        Invoice storage invoice = invoices[invoiceId];
        Invoice storage inv = invoices[invoiceId];
        uint256 total = escrow[invoiceId];

        if (inv.amount == 0) revert NotFound();
        if (!inv.paid) revert NotFullyPaid();
        if (inv.withdrawn) revert AlreadyWithdrawn();
        if (total < inv.amount) revert NotFullyPaid();

        inv.withdrawn = true;

        // send native ZETA
        if (inv.payoutToken == address(0)) {
            (bool ok, ) = inv.merchantWallet.call{value: total}("");
            if (!ok) revert TransferFailed();
        } else{
            // send ZRC-20 token
            if (!IZRC20(inv.payoutToken).transfer(inv.merchantWallet, total)) {
                revert TransferFailed();
            }
        }
        
        emit InvoiceWithdrawn(invoiceId, inv.merchantWallet, total);

        delete escrow[invoiceId];
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
