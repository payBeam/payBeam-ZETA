// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Invoice Management Contract
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";

contract PayBeamInvoice is Ownable, ReentrancyGuard {
    
    struct Invoice {
        address merchant;
        uint256 totalAmount;
        uint256 amountPaid;
        address denominationToken;
        uint256 expiration;
        bool isCompleted;
        mapping(address => bool) allowedTokens;
    }

    mapping(bytes32 => Invoice) public invoices;
    mapping(address => bool) public registeredMerchants;
    
    event InvoiceCreated(bytes32 indexed invoiceId, address merchant);
    event PaymentReceived(bytes32 indexed invoiceId, address payer, uint256 amount);
    event InvoiceCompleted(bytes32 indexed invoiceId);
    event Withdrawal(bytes32 indexed invoiceId, uint256 amount);

    modifier onlyMerchant() {
        require(registeredMerchants[msg.sender], "Not registered merchant");
        _;
    }

    constructor() {
        registeredMerchants[msg.sender] = true; // Initial admin
    }

    function registerMerchant(address merchant) external onlyOwner {
        registeredMerchants[merchant] = true;
    }

    function createInvoice(
        uint256 totalAmount,
        address denominationToken,
        address[] calldata allowedTokens,
        uint256 duration
    ) external onlyMerchant returns (bytes32 invoiceId) {
        invoiceId = keccak256(abi.encodePacked(msg.sender, block.timestamp, totalAmount));
        
        Invoice storage newInvoice = invoices[invoiceId];
        newInvoice.merchant = msg.sender;
        newInvoice.totalAmount = totalAmount;
        newInvoice.denominationToken = denominationToken;
        newInvoice.expiration = block.timestamp + duration;

        for (uint i = 0; i < allowedTokens.length; i++) {
            newInvoice.allowedTokens[allowedTokens[i]] = true;
        }

        emit InvoiceCreated(invoiceId, msg.sender);
    }

    function recordPayment(
        bytes32 invoiceId,
        address paymentToken,
        uint256 amount,
        address payer
    ) external nonReentrant {
        Invoice storage invoice = invoices[invoiceId];
        require(!invoice.isCompleted, "Invoice completed");
        require(block.timestamp < invoice.expiration, "Invoice expired");
        require(invoice.allowedTokens[paymentToken], "Token not allowed");

        // Convert amount to denomination token using oracle (implementation omitted for brevity)
        uint256 convertedAmount = convertToDenomination(paymentToken, amount);
        
        invoice.amountPaid += convertedAmount;
        if(invoice.amountPaid >= invoice.totalAmount) {
            invoice.isCompleted = true;
            emit InvoiceCompleted(invoiceId);
        }

        emit PaymentReceived(invoiceId, payer, convertedAmount);
    }

    function withdraw(bytes32 invoiceId) external nonReentrant {
        Invoice storage invoice = invoices[invoiceId];
        require(msg.sender == invoice.merchant, "Not merchant");
        require(invoice.isCompleted, "Invoice not complete");

        uint256 balance = IERC20(invoice.denominationToken).balanceOf(address(this));
        IERC20(invoice.denominationToken).transfer(invoice.merchant, balance);
        
        emit Withdrawal(invoiceId, balance);
    }

    function convertToDenomination(address token, uint256 amount) internal pure returns (uint256) {
        // Implement oracle-based conversion logic
        return amount; // Simplified for example
    }
}

// Escrow Contract
contract PayBeamEscrow is ReentrancyGuard {
    PayBeamInvoice public invoiceContract;
    
    constructor(address _invoiceContract) {
        invoiceContract = PayBeamInvoice(_invoiceContract);
    }

    function deposit(
        bytes32 invoiceId,
        address token,
        uint256 amount
    ) external nonReentrant {
        require(IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        invoiceContract.recordPayment(invoiceId, token, amount, msg.sender);
    }
}

// Updated Swap Contract
import "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";
import {SystemContract} from "@zetachain/toolkit/contracts/SystemContract.sol";
import {SwapHelperLib} from "@zetachain/toolkit/contracts/SwapHelperLib.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";

contract PayBeamSwap is UniversalContract, Ownable, ReentrancyGuard {
    PayBeamEscrow public escrow;
    address public uniswapRouter;
    uint256 public maxRevertAttempts = 3;
    mapping(bytes32 => uint256) public revertAttempts;

    GatewayZEVM public immutable gateway;

    error Unauthorized();

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    struct SwapParams {
        bytes32 invoiceId;
        uint256 minAmountOut;
        address targetToken;
        bytes recipient;
        bool withdraw;
    }

    event CrossChainSwap(
        bytes32 indexed invoiceId,
        address indexed sender,
        uint256 inputAmount,
        uint256 outputAmount
    );

    constructor(address payable gatewayAddress) {
        gateway = GatewayZEVM(gatewayAddress);
    }

    function swap(
        address inputToken,
        uint256 amount,
        SwapParams calldata params
    ) external nonReentrant {
        require(escrow.invoiceContract().allowedTokens(params.invoiceId, inputToken),
            "Token not allowed"
        );

        IERC20(inputToken).transferFrom(msg.sender, address(this), amount);
        
        (uint256 out, address gasZRC20, uint256 gasFee) = _executeSwap(
            inputToken,
            amount,
            params.targetToken,
            params.minAmountOut,
            params.withdraw
        );

        if(params.withdraw) {
            _handleWithdrawal(params, gasZRC20, gasFee, out);
        } else {
            escrow.deposit(params.invoiceId, params.targetToken, out);
        }

        emit CrossChainSwap(params.invoiceId, msg.sender, amount, out);
    }

    function onRevert(RevertContext calldata context) external override onlyGateway {
        bytes32 txHash = keccak256(abi.encode(context));
        require(revertAttempts[txHash] < maxRevertAttempts, "Max retries exceeded");
        revertAttempts[txHash]++;
        
        // Implement custom revert logic
        _handleFailedSwap(context);
    }

    // Internal implementation details omitted for brevity
    // Include improved swap logic with slippage protection
    // Add safe token transfer functions
    // Implement ZetaChain-specific cross-chain logic
}