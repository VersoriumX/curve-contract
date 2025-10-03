
# curve-contract

Vyper contracts for the VersoriumX ETHX Pool. This project is based on the original Curve protocol.

**Author:** Travis Jerome Goff
**Organization:** VersoriumX

## Overview

This repository contains the smart contracts for the ETHX liquidity pool. The pool is designed for efficient trading between ETHX, WETH, and ETH.

## Getting Started

### Dependencies

*   [Python](https://www.python.org/downloads/release/python-368/) (versions 3.6 to 3.8)
*   [Brownie](https://github.com/eth-brownie/brownie) (version 1.13.2 or later)
*   [Ganache CLI](https://github.com/trufflesuite/ganache-cli) (version 6.12.1 or later)

### Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/VersoriumX/curve-contract.git
    cd curve-contract
    ```

2.  **Create a virtual environment and install dependencies:**
    ```bash
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    ```

### Testing

To run the test suite:

```bash
brownie test
```

To run tests for a specific pool:

```bash
brownie test tests/ --pool <POOL_NAME>
```

### Deployment

To deploy a new pool:

1.  **Configure:** Update `pooldata.json` with the required pool data.
2.  **Deploy:**
    ```bash
    brownie run deploy --network <NETWORK_NAME>
    ```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
