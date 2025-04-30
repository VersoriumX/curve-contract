vyper
# @version 0.2.11
"""
@title Curve Pool Rate Calculator 
@author Curve.Fi
@license Copyright (c) Curve.Fi, 2021 - all rights reserved
@notice Logic for calculating exchange rate for a pool
@dev This contract is only a template, pool-specific logic
    must be added
"""

# Define addresses for WETH and ETHX
WETH_ADDRESS: constant(address) = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2  # Example WETH address (Mainnet)
ETHX_ADDRESS: constant(address) = 0x8487B97c91ecC1a03b4907B64Bdeab306B888c0E  # Example ETHX address

@view
@external
def get_rate(_coin: address) -> uint256:
    """
    @notice Get the exchange rate of a coin with respect to ETH.
    @param _coin The address of the coin to get the rate for.
    @return The exchange rate (1:1 = 10**18).
    """
    if _coin == WETH_ADDRESS or _coin == ETHX_ADDRESS:
        return 10**18  # 1:1 exchange rate
    else:
        return 0  # 0 for other coins (or implement more logic here)
