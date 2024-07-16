// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.23;

library Arrays {
    /* addressArray */
    function addressArray(address address0) internal pure returns (address[] memory) {
        address[] memory addresses = new address[](1);
        addresses[0] = address0;
        return addresses;
    }

    /* stringArray */
    function stringArray(string memory string0) internal pure returns (string[] memory) {
        string[] memory strings = new string[](1);
        strings[0] = string0;
        return strings;
    }

    function stringArray(string memory string0, string memory string1, string memory string2, string memory string3)
        internal
        pure
        returns (string[] memory)
    {
        string[] memory strings = new string[](4);
        strings[0] = string0;
        strings[1] = string1;
        strings[2] = string2;
        strings[3] = string3;
        return strings;
    }

    /* uintArray */
    function uintArray(uint256 uint0) internal pure returns (uint256[] memory) {
        uint256[] memory uints = new uint256[](1);
        uints[0] = uint0;
        return uints;
    }

    function uintArray(uint256 uint0, uint256 uint1, uint256 uint2, uint256 uint3)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory uints = new uint256[](4);
        uints[0] = uint0;
        uints[1] = uint1;
        uints[2] = uint2;
        uints[3] = uint3;
        return uints;
    }
}
