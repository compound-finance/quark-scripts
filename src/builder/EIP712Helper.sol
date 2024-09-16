// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {QuarkWalletMetadata} from "quark-core/src/QuarkWallet.sol";

import {Actions} from "./Actions.sol";
import {Errors} from "./Errors.sol";

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

    /* ===== Output Types ===== */

    /// @notice The structure containing EIP-712 data for a QuarkOperation or MultiQuarkOperation
    struct EIP712Data {
        // EIP-712 digest to sign for either a MultiQuarkOperation or a single QuarkOperation to fulfill the client intent.
        // The digest will be for a MultiQuarkOperation if there are more than one QuarkOperations in the BuilderResult.
        // Otherwise, the digest will be for a single QuarkOperation.
        bytes32 digest;
        // A unique identifier created by encoding and hashing domain-specific information for a QuarkOperation or MultiQuarkOperation
        bytes32 domainSeparator;
        // The hash of a structured data type and its values, as defined by EIP-712
        bytes32 hashStruct;
    }

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
     * @dev Returns the EIP-712 hashStruct for a QuarkOperation
     * @param op A QuarkOperation struct
     * @return EIP-712 hashStruct
     */
    function getHashStructForQuarkOperation(IQuarkWallet.QuarkOperation memory op) internal pure returns (bytes32) {
        bytes memory encodedScriptSources;
        for (uint256 i = 0; i < op.scriptSources.length; ++i) {
            encodedScriptSources = abi.encodePacked(encodedScriptSources, keccak256(op.scriptSources[i]));
        }

        return keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH,
                op.nonce,
                op.scriptAddress,
                keccak256(encodedScriptSources),
                keccak256(op.scriptCalldata),
                op.expiry
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
        bytes32 hashStruct = getHashStructForQuarkOperation(op);
        return keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(walletAddress, chainId), hashStruct));
    }

    /**
     * @dev Returns the EIP-712 hashStruct for a MultiQuarkOperation
     * @param ops A list of QuarkOperations in a MultiQuarkOperation
     * @param actions A list of Actions containing metadata for each QuarkOperation
     * @return EIP-712 hashStruct
     */
    function getHashStructForMultiQuarkOperation(
        IQuarkWallet.QuarkOperation[] memory ops,
        Actions.Action[] memory actions
    ) internal pure returns (bytes32) {
        if (ops.length != actions.length) {
            revert Errors.BadData();
        }

        bytes32[] memory opDigests = new bytes32[](ops.length);
        for (uint256 i = 0; i < ops.length; ++i) {
            opDigests[i] = getDigestForQuarkOperation(ops[i], actions[i].quarkAccount, actions[i].chainId);
        }

        bytes memory encodedOpDigests;
        for (uint256 i = 0; i < opDigests.length; ++i) {
            encodedOpDigests = abi.encodePacked(encodedOpDigests, opDigests[i]);
        }

        return keccak256(abi.encode(MULTI_QUARK_OPERATION_TYPEHASH, keccak256(encodedOpDigests)));
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
        bytes32 hashStruct = getHashStructForMultiQuarkOperation(ops, actions);
        return keccak256(abi.encodePacked("\x19\x01", MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR, hashStruct));
    }

    /**
     * @dev Returns EIP712Data struct for a list of quark operations (and actions)
     * @param quarkOperations A list of QuarkOperations in a MultiQuarkOperation
     * @param actions A list of Actions containing metadata for each QuarkOperation
     * @return eip712Data EIP712Data struct
     */
    function eip712DataForQuarkOperations(
        IQuarkWallet.QuarkOperation[] memory quarkOperations,
        Actions.Action[] memory actions
    ) internal pure returns (EIP712Data memory eip712Data) {
        if (quarkOperations.length == 1) {
            eip712Data = EIP712Data({
                digest: getDigestForQuarkOperation(quarkOperations[0], actions[0].quarkAccount, actions[0].chainId),
                domainSeparator: getDomainSeparator(actions[0].quarkAccount, actions[0].chainId),
                hashStruct: getHashStructForQuarkOperation(quarkOperations[0])
            });
        } else if (quarkOperations.length > 1) {
            eip712Data = EIP712Data({
                digest: getDigestForMultiQuarkOperation(quarkOperations, actions),
                domainSeparator: MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR,
                hashStruct: getHashStructForMultiQuarkOperation(quarkOperations, actions)
            });
        }
    }
}
