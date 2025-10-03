# ethx-pool

**author:** Travis Jerome Goff
**organization:** VersoriumX

[ETHX Pool](https://versoriumx.com). This is a no-lending pool designed for ETHX, WETH and ETH.

## Contracts

-   `StableSwapETHX` ([StableSwapETHX.vy](StableSwapETHX.vy)): ETHX stablecoin AMM contract.
    -   **Deployment Address:** TBD
-   `CurveTokenV3` ([../../tokens/CurveTokenV3.vy](../../tokens/CurveTokenV3.vy)): [0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c](https://etherscan.io/address/0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c)
-   `LiquidityGaugeV2` ([LiquidityGaugeV2.vy](https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/gauges/LiquidityGaugeV2.vy)): [0x3C0FFFF15EA30C35d7A85B85c0782D6c94e1d238](https://etherscan.io/address/0x3C0FFFF15EA30C35d7A85B85c0782D6c94e1d238)

## Assets

The ETHX pool supports swaps between ETHX, WETH, and ETH.

-   `ETHX`: [0x8487B97c91ecC1a03b4907B64Bdeab306B888c0E](https://etherscan.io/address/0x8487B97c91ecC1a03b4907B64Bdeab306B888c0E)
-   `WETH`: [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
-   `ETH`: represented in the pool as `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`
