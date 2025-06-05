// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RevertContext, RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import "@zetachain/protocol-contracts/contracts/evm/GatewayEVM.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "./Paybeam.sol";

contract PaybeamConnected is Ownable {
    using SafeERC20 for IERC20;

    GatewayEVM public immutable gateway;
    // PayBeamUniversal public immutable payBeam;
    address public counterParty;

    error Unauthorized();

    event PingEvent(string indexed greeting, string message);
    event RevertEvent(string indexed message, RevertContext revertContext);

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    constructor(address gatewayAddress, address initialOwner) Ownable(initialOwner) {
        gateway = GatewayEVM(gatewayAddress);
        // payBeam = PayBeamUniversal(payBeamAddress);
    }

    function setCounterParty(address _counterParty) external onlyOwner {
        counterParty = _counterParty;
    }

    function deposit(
        address receiver,
        RevertOptions memory revertOptions
    ) external payable {
        gateway.deposit{ value: msg.value }(receiver, revertOptions);
    }

    function depositAndCall(
        bytes32 invoiceId,
        address receiver,
        uint256 amount,
        address asset,
        bytes calldata message,
        RevertOptions memory revertOptions
    ) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(gateway), amount);
        gateway.depositAndCall(receiver, amount,  asset, message, revertOptions);
    }

    function payNativeCrossChain(
        bytes32 invoiceId,
        address payerAddressOnZEVM,
        RevertOptions memory revertOptions
    ) external payable {
        bytes memory message = abi.encode(invoiceId, payerAddressOnZEVM);
        
        gateway.depositAndCall{ value: msg.value }(
            payerAddressOnZEVM,
            message,
            revertOptions
        );
    }

     function ping(string memory message) external payable {
        emit PingEvent("Hello on EVM", message);
    }

    function onCall(
        MessageContext calldata context,
        bytes calldata message
    ) external payable onlyGateway returns (bytes4) {
        emit PingEvent("Hello on EVM from onCall()", "hello there");
        return "";
    }

    function onRevert(
        RevertContext calldata revertContext
    ) external onlyGateway {
        emit RevertEvent("Revert on EVM", revertContext);
    }


    // --- Fallback functions ---
    receive() external payable {}
    fallback() external payable {}
}

