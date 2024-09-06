#!/bin/bash

# This script searches for custom Solidity error declarations in the ./lib and ./src directories,
# excluding any files with 'test' or 'mock' in their names.

# Run the grep command to find error declarations
grep -r "error [A-Z]" ./lib ./src --include \*.sol --exclude '*test*' --exclude '*mock*'
