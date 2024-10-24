// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IAcrossV3SpokePool} from "./interfaces/IAcrossV3SpokePool.sol";

contract AcrossActions {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    /**
     * @notice Bridge an asset to the destination chain by depositing it into the Across v3 SpokePool
     * @param spokePool The address of the Across v3 SpokePool contract
     * @param depositor The account credited with the deposit
     * @param recipient The account receiving funds on the destination chain. Can be an EOA or a contract. If
     * the output token is the wrapped native token for the chain, then the recipient will receive native token if
     * an EOA or wrapped native token if a contract
     * @param inputToken The token pulled from the caller's account and locked into this contract to
     * initiate the deposit. If this is equal to the wrapped native token then the caller can optionally pass in native
     * token as msg.value, as long as msg.value = inputTokenAmount
     * @param outputToken The token that the relayer will send to the recipient on the destination chain. Must be an
     * ERC20
     * @param inputAmount The amount of input tokens to pull from the caller's account and lock into this contract
     * @param outputAmount The amount of output tokens that the relayer will send to the recipient on the destination
     * @param destinationChainId The destination chain identifier
     * @param exclusiveRelayer The relayer that will be exclusively allowed to fill this deposit before the
     * exclusivity deadline timestamp. This must be a valid, non-zero address if the exclusivity deadline is
     * greater than the current block.timestamp. If the exclusivity deadline is < currentTime, then this must be
     * address(0), and vice versa if this is address(0)
     * @param quoteTimestamp The HubPool timestamp that is used to determine the system fee paid by the depositor.
     * This must be set to some time between [currentTime - depositQuoteTimeBuffer, currentTime]
     * where currentTime is block.timestamp on this chain or this transaction will revert
     * @param fillDeadline The deadline for the relayer to fill the deposit. After this destination chain timestamp,
     * the fill will revert on the destination chain. Must be set between [currentTime, currentTime + fillDeadlineBuffer]
     * where currentTime is block.timestamp on this chain or this transaction will revert
     * @param exclusivityDeadline The deadline for the exclusive relayer to fill the deposit. After this
     * destination chain timestamp, anyone can fill this deposit on the destination chain. If exclusiveRelayer is set
     * to address(0), then this also must be set to 0, (and vice versa), otherwise this must be set >= current time.
     * @param message The message to send to the recipient on the destination chain if the recipient is a contract
     * If the message is not empty, the recipient contract must implement handleV3AcrossMessage() or the fill will revert
     * @param useNativeToken Whether or not the native token (e.g. ETH) should be used as the input token
     */
    function depositV3(
        address spokePool,
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message,
        bool useNativeToken
    ) external payable {
        IERC20(inputToken).forceApprove(spokePool, inputAmount);

        IAcrossV3SpokePool(spokePool).depositV3{value: useNativeToken ? inputAmount : 0}({
            depositor: depositor,
            recipient: recipient,
            inputToken: inputToken,
            outputToken: outputToken,
            inputAmount: inputAmount,
            outputAmount: outputAmount,
            destinationChainId: destinationChainId,
            exclusiveRelayer: exclusiveRelayer,
            quoteTimestamp: quoteTimestamp,
            fillDeadline: fillDeadline,
            exclusivityDeadline: exclusivityDeadline,
            message: message
        });
    }
}
