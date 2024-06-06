// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

library BridgeRoutes {
    enum BridgeType {
        NONE,
        CCTP
    }

    uint256 constant BASE_CHAIN_ID = 8453;
    uint256 constant MAINNET_CHAIN_ID = 1;

    mapping(uint256 => uint32) public chainIdToCCTPDomainId;

    constructor() {
        // Right now we only have Mainnet and Base
        chainIdToCCTPDomainId[MAINNET_CHAIN_ID] = 0;
        chainIdToCCTPDomainId[BASE_CHAIN_ID] = 6;
    }

    struct Bridge {
        // Note: Cannot name these `address` nor `type` because those are both reserved keywords
        address bridgeAddress;
        BridgeType bridgeType;
        uint32 domainId;
    }

    function hasBridge(uint256 srcChainId, uint256 dstChainId, string memory assetSymbol) internal pure returns (bool) {
        if (getBridge(srcChainId, dstChainid, assetSymbol).bridgeType == BridgeType.NONE) {
            return false;
        } else {
            return true;
        }
    }

    function getBridge(uint256 srcChainId, uint256 dstChainId, string memory assetSymbol) internal pure returns (Bridge memory) {
        if (srcChainId == 1) {
            return getBridgeForMainnet(dstChainId, assetSymbol);
        } else if (srcChainId == 8453) {
            return getBridgeForBase(dstChainId, assetSymbol);
        } else {
            return Bridge({
                    bridgeAddress: address(0),
                    bridgeType: BridgeType.NONE
                });
            // revert BridgeNotFound(1, dstChainid, assetSymbol);
        }
    }

    function getBridge(uint256 srcChainId, uint256 dstChainId, string memory assetSymbol) internal pure returns (Bridge memory) {
        if (srcChainId == MAINNET_CHAIN_ID) {
            return getBridgeForMainnet(dstChainId, assetSymbol);
        } else if (srcChainId == BASE_CHAIN_ID) {
            return getBridgeForBase(dstChainId, assetSymbol);
        } else {
            return Bridge({
                    bridgeAddress: address(0),
                    bridgeType: BridgeType.NONE
                });
            // revert BridgeNotFound(1, dstChainid, assetSymbol);
        }
    }

    function getBridgeForMainnet(uint256 dstChainId, string memory assetSymbol) internal pure returns (Bridge memory) {
        if (dstChainId == MAINNET_CHAIN_ID) {
            revert("Cannot bridge to the same chain");
        }

        if (compareStrings(assetSymbol, "USDC")) {
            return Bridge({
                bridgeAddress: 0xBd3fa81B58Ba92a82136038B25aDec7066af3155,
                bridgeType: BridgeType.CCTP, 
                domainId: chainIdToCCTPDomainId[dstChainId]
            });
        } else {
            return Bridge({
                bridgeAddress: address(0),
                bridgeType: BridgeType.NONE
            });
            // revert BridgeNotFound(1, dstChainid, assetSymbol);
        }
    }

    function getBridgeForBase(uint256 dstChainId, string memory assetSymbol) internal pure returns (Bridge memory) {
        if (dstChainId == BASE_CHAIN_ID) {
            revert("Cannot bridge to the same chain");
        }
        
        if (compareStrings(assetSymbol, "USDC")) {
            return Bridge({
                bridgeAddress: 0x1682Ae6375C4E4A97e4B583BC394c861A46D8962,
                bridgeType: BridgeType.CCTP, 
                domainId: chainIdToCCTPDomainId[dstChainId]
            });
        } else {
            return Bridge({
                bridgeAddress: address(0),
                bridgeType: BridgeType.NONE
            });
            // revert BridgeNotFound(1, dstChainid, assetSymbol);
        }
    }
}
