// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {QuarkWalletMetadata} from "quark-core/src/QuarkWallet.sol";

import {Actions} from "./Actions.sol";

library EIP712Helper {
    /* ===== Constants ===== */

    /// @notice The name of the Quark Wallet contract to construct an EIP712 digest for
    string internal constant QUARK_WALLET_NAME = QuarkWalletMetadata.NAME;

    /// @notice The version of the Quark Wallet contract to construct an EIP712 digest for
    string internal constant QUARK_WALLET_VERSION = QuarkWalletMetadata.VERSION;

    /// @dev The EIP-712 domain typehash for this wallet
    bytes32 internal constant DOMAIN_TYPEHASH = QuarkWalletMetadata.DOMAIN_TYPEHASH;

    /// @dev The EIP-712 domain typehash used for MultiQuarkOperations for this wallet
    bytes32 internal constant MULTI_QUARK_OPERATION_DOMAIN_TYPEHASH =
        QuarkWalletMetadata.MULTI_QUARK_OPERATION_DOMAIN_TYPEHASH;

    /// @dev The EIP-712 typehash for authorizing an operation for this wallet
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = QuarkWalletMetadata.QUARK_OPERATION_TYPEHASH;

    /// @dev The EIP-712 typehash for authorizing an operation that is part of a MultiQuarkOperation for this wallet
    bytes32 internal constant MULTI_QUARK_OPERATION_TYPEHASH = QuarkWalletMetadata.MULTI_QUARK_OPERATION_TYPEHASH;

    /// @dev The EIP-712 typehash for authorizing an EIP-1271 signature for this wallet
    bytes32 internal constant QUARK_MSG_TYPEHASH = QuarkWalletMetadata.QUARK_MSG_TYPEHASH;

    /// @dev The EIP-712 domain separator for a MultiQuarkOperation
    /// @dev Note: `chainId` and `verifyingContract` are left out so a single MultiQuarkOperation can be used to
    ///            execute operations on different chains and wallets.
    bytes32 internal constant MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            QuarkWalletMetadata.MULTI_QUARK_OPERATION_DOMAIN_TYPEHASH,
            keccak256(bytes(QuarkWalletMetadata.NAME)),
            keccak256(bytes(QuarkWalletMetadata.VERSION))
        )
    );

    /* ===== Custom Errors ===== */

    error BadData();

    /**
     * @dev Returns the domain separator for a Quark wallet
     * @param walletAddress The Quark wallet address that the domain separator is scoped to
     * @param chainId The chain id that the domain separator is scoped to
     * @return Domain separator
     */
    function getDomainSeparator(address walletAddress, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(QUARK_WALLET_NAME)),
                keccak256(bytes(QUARK_WALLET_VERSION)),
                chainId,
                walletAddress
            )
        );
    }

    /**
     * @dev Returns the EIP-712 digest for a QuarkOperation
     * @param op A QuarkOperation struct
     * @param walletAddress The Quark wallet address that the domain separator is scoped to
     * @param chainId The chain id that the domain separator is scoped to
     * @return EIP-712 digest
     */
    function getDigestForQuarkOperation(IQuarkWallet.QuarkOperation memory op, address walletAddress, uint256 chainId)
        internal
        pure
        returns (bytes32)
    {
        bytes memory encodedScriptSources;
        for (uint256 i = 0; i < op.scriptSources.length; ++i) {
            encodedScriptSources = abi.encodePacked(encodedScriptSources, keccak256(op.scriptSources[i]));
        }

        bytes32 structHash = keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH,
                op.nonce,
                op.scriptAddress,
                keccak256(encodedScriptSources),
                keccak256(op.scriptCalldata),
                op.expiry
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(walletAddress, chainId), structHash));
    }

    /**
     * @dev Returns the EIP-712 digest for a MultiQuarkOperation
     * @param opDigests A list of EIP-712 digests for the operations in a MultiQuarkOperation
     * @return EIP-712 digest
     */
    function getDigestForMultiQuarkOperation(bytes32[] memory opDigests) internal pure returns (bytes32) {
        bytes memory encodedOpDigests;
        for (uint256 i = 0; i < opDigests.length; ++i) {
            encodedOpDigests = abi.encodePacked(encodedOpDigests, opDigests[i]);
        }

        bytes32 structHash = keccak256(abi.encode(MULTI_QUARK_OPERATION_TYPEHASH, keccak256(encodedOpDigests)));
        return keccak256(abi.encodePacked("\x19\x01", MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR, structHash));
    }

    /**
     * @dev Returns the EIP-712 digest for a MultiQuarkOperation
     * @param ops A list of QuarkOperations in a MultiQuarkOperation
     * @param actions A list of Actions containing metadata for each QuarkOperation
     * @return EIP-712 digest
     */
    function getDigestForMultiQuarkOperation(IQuarkWallet.QuarkOperation[] memory ops, Actions.Action[] memory actions)
        internal
        pure
        returns (bytes32)
    {
        if (ops.length != actions.length) {
            revert BadData();
        }

        bytes32[] memory opDigests = new bytes32[](ops.length);
        for (uint256 i = 0; i < ops.length; ++i) {
            opDigests[i] = getDigestForQuarkOperation(ops[i], actions[i].quarkAccount, actions[i].chainId);
        }
        return getDigestForMultiQuarkOperation(opDigests);
    }
}
