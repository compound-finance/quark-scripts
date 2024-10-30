// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.27;

import {QuarkBuilder} from "./QuarkBuilder.sol";
import {CCTPBridgeActions} from "../BridgeScripts.sol";

import "./Strings.sol";

library BridgeRoutes {
    function canBridge(uint256 srcChainId, uint256 dstChainId, string memory assetSymbol)
        internal
        pure
        returns (bool)
    {
        return CCTP.canBridge(srcChainId, dstChainId, assetSymbol);
    }
}

library CCTP {
    error NoKnownBridge(string bridgeType, uint256 srcChainId);
    error NoKnownDomainId(string bridgeType, uint256 dstChainId);

    struct CCTPChain {
        uint256 chainId;
        uint32 domainId;
        address bridge;
    }

    // @dev Source: TokenMessenger contract from https://developers.circle.com/stablecoins/evm-smart-contracts
    function knownChains() internal pure returns (CCTPChain[] memory) {
        CCTPChain[] memory chains = new CCTPChain[](6);
        // Mainnet
        chains[0] = CCTPChain({chainId: 1, domainId: 0, bridge: 0xBd3fa81B58Ba92a82136038B25aDec7066af3155});
        // Base
        chains[1] = CCTPChain({chainId: 8453, domainId: 6, bridge: 0x1682Ae6375C4E4A97e4B583BC394c861A46D8962});
        // Arbitrum
        chains[2] = CCTPChain({chainId: 42161, domainId: 3, bridge: 0x19330d10D9Cc8751218eaf51E8885D058642E08A});
        // Sepolia
        chains[3] = CCTPChain({chainId: 11155111, domainId: 0, bridge: 0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5});
        // Base Sepolia
        chains[4] = CCTPChain({chainId: 84532, domainId: 6, bridge: 0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5});
        // Arbitrum Sepolia
        chains[5] = CCTPChain({chainId: 421614, domainId: 3, bridge: 0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5});
        return chains;
    }

    function knownChain(uint256 chainId) internal pure returns (CCTPChain memory found) {
        CCTPChain[] memory cctpChains = knownChains();
        for (uint256 i = 0; i < cctpChains.length; ++i) {
            if (cctpChains[i].chainId == chainId) {
                return found = cctpChains[i];
            }
        }
    }

    function canBridge(uint256 srcChainId, uint256 dstChainId, string memory assetSymbol)
        internal
        pure
        returns (bool)
    {
        return Strings.stringEqIgnoreCase(assetSymbol, "USDC") && knownChain(srcChainId).bridge != address(0)
            && knownChain(dstChainId).chainId == dstChainId;
    }

    function knownDomainId(uint256 dstChainId) internal pure returns (uint32) {
        CCTPChain memory chain = knownChain(dstChainId);
        if (chain.chainId != 0) {
            return chain.domainId;
        } else {
            revert NoKnownDomainId("CCTP", dstChainId);
        }
    }

    function knownBridge(uint256 srcChainId) internal pure returns (address) {
        CCTPChain memory chain = knownChain(srcChainId);
        if (chain.bridge != address(0)) {
            return chain.bridge;
        } else {
            revert NoKnownBridge("CCTP", srcChainId);
        }
    }

    function bridgeScriptSource() internal pure returns (bytes memory) {
        return type(CCTPBridgeActions).creationCode;
    }

    function encodeBridgeUSDC(
        uint256 srcChainId,
        uint256 dstChainId,
        uint256 amount,
        address recipient,
        address usdcAddress
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            CCTPBridgeActions.bridgeUSDC.selector,
            knownBridge(srcChainId),
            amount,
            knownDomainId(dstChainId),
            bytes32(uint256(uint160(recipient))),
            usdcAddress
        );
    }
}
