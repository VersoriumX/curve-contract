# interact_curve.py

import os
import json
from dotenv import load_dotenv
from web3 import Web3

# 1. Load environment variables
load_dotenv()
WEB3_PROVIDER_URL = os.getenv("WEB3_PROVIDER_URL")
if not WEB3_PROVIDER_URL:
    raise ValueError("WEB3_PROVIDER_URL not set in .env file")

# 2. Connect to an Ethereum node
w3 = Web3(Web3.HTTPProvider(WEB3_PROVIDER_URL))

if not w3.is_connected():
    print(f"Failed to connect to Ethereum node at {WEB3_PROVIDER_URL}")
    exit()
else:
    print(f"Successfully connected to Ethereum node at {WEB3_PROVIDER_URL}")
    print(f"Current block number: {w3.eth.block_number}")

# 3. Curve Contract Information (Example: Curve 3pool token)
#    Replace with the actual contract you want to interact with
CURVE_3POOL_TOKEN_ADDRESS = "0x6c3F90f043a72fa612cbac8115EE7e52BDe6E490"

# Load the ABI from a file
try:
    with open("curve_3pool_abi.json", "r") as f:
        CURVE_3POOL_TOKEN_ABI = json.load(f)
except FileNotFoundError:
    print("Error: curve_3pool_abi.json not found. Please create it.")
    exit()

# 4. Create a contract instance
curve_token_contract = w3.eth.contract(address=Web3.to_checksum_address(CURVE_3POOL_TOKEN_ADDRESS), abi=CURVE_3POOL_TOKEN_ABI)

# 5. Interact with the contract (Read-only examples)

print(f"\n--- Interacting with Curve 3Pool Token ({CURVE_3POOL_TOKEN_ADDRESS}) ---")

# Example 1: Get Total Supply
try:
    total_supply = curve_token_contract.functions.totalSupply().call()
    # Most ERC-20 tokens have 18 decimal places, Curve tokens too
    total_supply_formatted = w3.from_wei(total_supply, 'ether')
    print(f"Total Supply: {total_supply_formatted} 3CRV")
except Exception as e:
    print(f"Error getting total supply: {e}")

# Example 2: Get Symbol
try:
    symbol = curve_token_contract.functions.symbol().call()
    print(f"Symbol: {symbol}")
except Exception as e:
    print(f"Error getting symbol: {e}")

# Example 3: Get Name
try:
    name = curve_token_contract.functions.name().call()
    print(f"Name: {name}")
except Exception as e:
    print(f"Error getting name: {e}")

# Example 4: Get balance of an address (replace with an actual address)
# A large exchange address or a known Curve liquidity provider
example_address = "0xd2d062F7649d2E302A4f964F19b068D2e379432f" # Example: A known large 3CRV holder (aave v2 wrapper)
try:
    balance = curve_token_contract.functions.balanceOf(Web3.to_checksum_address(example_address)).call()
    balance_formatted = w3.from_wei(balance, 'ether')
    print(f"Balance of {example_address}: {balance_formatted} 3CRV")
except Exception as e:
    print(f"Error getting balance for {example_address}: {e}")

print("\n--- Interaction complete ---")

# To send transactions (e.g., approve, transfer, add_liquidity, remove_liquidity)
# you would need:
# - A private key loaded from .env (NEVER hardcode!)
# - Your account address
# - Build, sign, and send the transaction
# This is more complex and involves gas estimation, nonces, etc.
# Example (conceptual):
# from_address = w3.eth.account.from_key(os.getenv("PRIVATE_KEY")).address
# nonce = w3.eth.get_transaction_count(from_address)
# transaction = curve_token_contract.functions.transfer(
#     recipient_address, amount_in_wei
# # ).build_transaction({
# #     'chainId': w3.eth.chain_id,
# #     'gas': 200000, # Estimate properly!
# #     'gasPrice': w3.eth.gas_price,
# #     'nonce': nonce,
# #     'from': from_address
# # })
# # signed_txn = w3.eth.account.sign_transaction(transaction, private_key)
# # tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
# # print(f"Transaction sent: {tx_hash.hex()}")
