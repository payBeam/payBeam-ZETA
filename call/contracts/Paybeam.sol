// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RevertContext, RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";

contract PayBeamUniversal is UniversalContract {
    GatewayZEVM public immutable gateway;
    address       public relayer;

    struct Invoice {
        address payoutToken;      // ZRC-20 or address(0) for native ZETA
        uint256 amount;           // total due
        address merchantWallet;   // where funds go on withdraw
        address merchantId;       // off-chain merchant reference
        bool  paid;             // reached threshold?
        bool withdrawn;        // funds sent out?
    }

    mapping(bytes32 => Invoice) public invoices;
    mapping(bytes32 => uint256) public escrow;       // total held
    mapping(bytes32 => address[]) public payers;       // who’s paid
    mapping(bytes32 => mapping(address => uint256)) public payments; // how much

    // --- Events ---
    event InvoiceCreated(
        bytes32 indexed invoiceId,
        address indexed merchantId,
        address payoutToken,
        uint256 amount,
        address merchantWallet
    );
    event PaymentReceived(
        bytes32 indexed invoiceId,
        address indexed payer,
        address  token,
        uint256  amount,
        uint256  totalEscrowed
    );
    event InvoiceFullyPaid(bytes32 indexed invoiceId);
    event InvoiceWithdrawn(
        bytes32 indexed invoiceId,
        address indexed merchantWallet,
        uint256 amount
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

    constructor(address payable gatewayAddress, address _relayer) {
        gateway = GatewayZEVM(gatewayAddress);
        relayer  = _relayer;
    }

    function setRelayer(address _newRelayer) external onlyRelayer {
        relayer = _newRelayer;
    }

    /// @notice Backend-only: create a new invoice
    function createInvoice(
        bytes32 invoiceId,
        address payoutToken,
        uint256 amount,
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
            withdrawn:      false
        });

        emit InvoiceCreated( invoiceId, merchantId, payoutToken, amount, merchantWallet);
    }

    /// @notice Same-chain native ZETA deposit
    function payInvoice(bytes32 invoiceId) external payable {
        _recordPayment(invoiceId, msg.sender, address(0), msg.value);
    }

    /// @notice Cross-chain deposit via ZetaChain Gateway
    /// @param ctx          Zeta-chain message context
    /// @param zrc20        token (address(0) for native)
    /// @param amount       amount received
    /// @param message      abi.encode(invoiceId, payer)
    function onCall(
        MessageContext calldata ctx,
        address               zrc20,
        uint256               amount,
        bytes    calldata     message
    ) external override onlyGateway {
        (bytes32 invoiceId, address payer) = abi.decode(message, (bytes32, address));
        _recordPayment(invoiceId, payer, zrc20, amount);
    }

    /// @dev Records any payment source, marks paid when threshold met.
    function _recordPayment(
        bytes32 invoiceId,
        address payer,
        address token,
        uint256 amount
    ) internal {
        Invoice storage inv = invoices[invoiceId];
        if (inv.amount == 0) revert NotFound();
        if (inv.withdrawn) revert AlreadyWithdrawn();

        // record payer
        if (payments[invoiceId][payer] == 0) {
            payers[invoiceId].push(payer);
        }

        payments[invoiceId][payer] += amount;
        escrow[invoiceId]           += amount;

        emit PaymentReceived(
            invoiceId,
            payer,
            token,
            amount,
            escrow[invoiceId]
        );

        // mark fully paid once escrow ≥ amount
        if (!inv.paid && escrow[invoiceId] >= inv.amount) {
            inv.paid = true;
            emit InvoiceFullyPaid(invoiceId);
        }
    }

    /// @notice Backend-only: withdraw full escrow to merchant wallet
    function withdrawInvoice(bytes32 invoiceId) external onlyRelayer {
        Invoice storage inv = invoices[invoiceId];
        uint256 total = escrow[invoiceId];

        if (inv.amount == 0) revert NotFound();
        if (!inv.paid) revert NotFullyPaid();
        if (inv.withdrawn) revert AlreadyWithdrawn();
        if (total < inv.amount) revert NotFullyPaid();

        inv.withdrawn = true;

        // send native ZETA
        (bool ok, ) = inv.merchantWallet.call{ value: total }("");
        if (!ok) revert TransferFailed();

        emit InvoiceWithdrawn(invoiceId, inv.merchantWallet, total);

        delete escrow[invoiceId];
    }

    // --- Unused ZetaChain callbacks (stubs) ---
    function onRevert(RevertContext calldata) external override onlyGateway {}
    function onAbort(AbortContext calldata) external override onlyGateway {}

    receive() external payable {}
}
