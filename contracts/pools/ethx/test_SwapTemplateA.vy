# tests/test_SwapTemplateA.vy

import pytest
from eth_tester.exceptions import TransactionFailed
from vyper.utils import parse_bytes32

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
MAX_UINT256 = 2**256 - 1

# Define constants based on the contract template
N_COINS = 2
PRECISION_MUL = [10**18, 10**18]  # Example precision multipliers
A = 1000
FEE = 4 * 10**6  # 0.04%
ADMIN_FEE = 5 * 10**9  # 50%
OFFPEG_FEE_MULTIPLIER = 10**10  # 1x

@pytest.fixture
def coins(accounts, ERC20):
    return [ERC20.deploy("Coin1", "C1", 18, 10**24, {"from": accounts[0]}),
            ERC20.deploy("Coin2", "C2", 18, 10**24, {"from": accounts[0]})]

@pytest.fixture
def underlying_coins(accounts, ERC20):
    return [ERC20.deploy("uCoin1", "uC1", 18, 10**24, {"from": accounts[0]}),
            ERC20.deploy("uCoin2", "uC2", 18, 10**24, {"from": accounts[0]})]

@pytest.fixture
def lp_token(accounts, CurveToken):
    return CurveToken.deploy("Curve LP Token", "CRVLP", {"from": accounts[0]})

@pytest.fixture
def lending_pool(accounts, LendingPool):
    return LendingPool.deploy({"from": accounts[0]})


@pytest.fixture
def swap_template(accounts, coins, underlying_coins, lp_token, lending_pool, SwapTemplateA):
    swap = SwapTemplateA.deploy(
        [c.address for c in coins],
        [uc.address for uc in underlying_coins],
        lp_token.address,
        lending_pool.address,
        A,
        FEE,
        ADMIN_FEE,
        OFFPEG_FEE_MULTIPLIER,
        {"from": accounts[0]}
    )
    # Approve the swap contract to spend coins and underlying coins for the owner
    for coin in coins + underlying_coins:
        coin.approve(swap.address, MAX_UINT256, {"from": accounts[0]})
    return swap

def test_initialization(swap_template, coins, underlying_coins, lp_token, lending_pool, accounts):
    assert swap_template.owner() == accounts[0]
    assert swap_template.lp_token() == lp_token.address
    assert swap_template.aave_lending_pool() == lending_pool.address
    assert swap_template.initial_A() == A * 100
    assert swap_template.future_A() == A * 100
    assert swap_template.fee() == FEE
    assert swap_template.admin_fee() == ADMIN_FEE
    assert swap_template.offpeg_fee_multiplier() == OFFPEG_FEE_MULTIPLIER
    assert swap_template.is_killed() == False
    for i in range(N_COINS):
        assert swap_template.coins(i) == coins[i].address
        assert swap_template.underlying_coins(i) == underlying_coins[i].address

def test_add_liquidity(swap_template, coins, underlying_coins, lp_token, accounts):
    amounts = [10**18, 10**18]  # 1 token of each
    min_mint_amount = 0

    # Test with wrapped coins
    lp_token.approve(swap_template.address, MAX_UINT256, {"from": accounts[0]})
    initial_lp_balance = lp_token.balanceOf(accounts[0])
    initial_coin_balances = [c.balanceOf(swap_template.address) for c in coins]

    minted_amount = swap_template.add_liquidity(amounts, min_mint_amount, False, {"from": accounts[0]})

    assert lp_token.balanceOf(accounts[0]) == initial_lp_balance + minted_amount
    for i in range(N_COINS):
        assert coins[i].balanceOf(swap_template.address) == initial_coin_balances[i] + amounts[i]

    # Test with underlying coins
    lp_token.approve(swap_template.address, MAX_UINT256, {"from": accounts[0]})
    initial_lp_balance = lp_token.balanceOf(accounts[0])
    initial_underlying_coin_balances = [uc.balanceOf(swap_template.address) for uc in underlying_coins]

    minted_amount_underlying = swap_template.add_liquidity(amounts, min_mint_amount, True, {"from": accounts[0]})

    assert lp_token.balanceOf(accounts[0]) == initial_lp_balance + minted_amount_underlying
    # underlying coins are deposited into the lending pool, so their balance on the swap contract remains unchanged
    for i in range(N_COINS):
         assert underlying_coins[i].balanceOf(swap_template.address) == initial_underlying_coin_balances[i]

    # Test with zero initial deposit amount
    amounts_zero = [0, 0]
    with pytest.raises(TransactionFailed):
        swap_template.add_liquidity(amounts_zero, min_mint_amount, False, {"from": accounts[0]})

    # Test minimum mint amount requirement
    amounts_small = [100, 100]
    with pytest.raises(TransactionFailed):
        swap_template.add_liquidity(amounts_small, 10**18, False, {"from": accounts[0]})

def test_remove_liquidity(swap_template, coins, underlying_coins, lp_token, accounts):
    # Add initial liquidity
    amounts = [10**18, 10**18]
    lp_token.approve(swap_template.address, MAX_UINT256, {"from": accounts[0]})
    swap_template.add_liquidity(amounts, 0, False, {"from": accounts[0]})

    total_lp_supply = lp_token.totalSupply()
    remove_amount = total_lp_supply // 2
    min_amounts = [0, 0]

    # Test with wrapped coins
    initial_lp_balance = lp_token.balanceOf(accounts[0])
    initial_coin_balances = [c.balanceOf(accounts[0]) for c in coins]

    removed_amounts = swap_template.remove_liquidity(remove_amount, min_amounts, False, {"from": accounts[0]})

    assert lp_token.balanceOf(accounts[0]) == initial_lp_balance - remove_amount
    for i in range(N_COINS):
        assert coins[i].balanceOf(accounts[0]) >= initial_coin_balances[i] + removed_amounts[i]  # Account for potential dust

    # Test with underlying coins
    lp_token.approve(swap_template.address, MAX_UINT256, {"from": accounts[0]})
    swap_template.add_liquidity(amounts, 0, True, {"from": accounts[0]}) # Add liquidity as underlying
    total_lp_supply_underlying = lp_token.totalSupply()
    remove_amount_underlying = total_lp_supply_underlying - total_lp_supply
    initial_underlying_coin_balances = [uc.balanceOf(accounts[0]) for uc in underlying_coins]

    removed_amounts_underlying = swap_template.remove_liquidity(remove_amount_underlying, min_amounts, True, {"from": accounts[0]})

    assert lp_token.balanceOf(accounts[0]) == initial_lp_balance - remove_amount + remove_amount_underlying - remove_amount_underlying # Should be back to initial after both removes
    for i in range(N_COINS):
        assert underlying_coins[i].balanceOf(accounts[0]) >= initial_underlying_coin_balances[i] + removed_amounts_underlying[i]

    # Test minimum amount requirement
    with pytest.raises(TransactionFailed):
        swap_template.remove_liquidity(remove_amount, [10**20, 10**20], False, {"from": accounts[0]})

def test_remove_liquidity_imbalance(swap_template, coins, underlying_coins, lp_token, accounts):
    # Add initial liquidity
    amounts = [10**18, 10**18]
    lp_token.approve(swap_template.address, MAX_UINT256, {"from": accounts[0]})
    swap_template.add_liquidity(amounts, 0, False, {"from": accounts[0]})

    remove_amounts = [0, 5 * 10**17]  # Remove 0.5 of coin 2
    max_burn_amount = lp_token.totalSupply()

    # Test with wrapped coins
    initial_lp_balance = lp_token.balanceOf(accounts[0])
    initial_coin_balances = [c.balanceOf(accounts[0]) for c in coins]

    burned_amount = swap_template.remove_liquidity_imbalance(remove_amounts, max_burn_amount, False, {"from": accounts[0]})

    assert lp_token.balanceOf(accounts[0]) == initial_lp_balance - burned_amount
    assert coins[0].balanceOf(accounts[0]) == initial_coin_balances[0] + remove_amounts[0]
    assert coins[1].balanceOf(accounts[0]) == initial_coin_balances[1] + remove_amounts[1]

    # Test with underlying coins
    lp_token.approve(swap_template.address, MAX_UINT256, {"from": accounts[0]})
    swap_template.add_liquidity(amounts, 0, True, {"from": accounts[0]}) # Add liquidity as underlying
    remove_amounts_underlying = [5 * 10**17, 0] # Remove 0.5 of underlying coin 1
    max_burn_amount_underlying = lp_token.totalSupply() - (lp_token.totalSupply() - initial_lp_balance) # Only consider the underlying deposit
    initial_underlying_coin_balances = [uc.balanceOf(accounts[0]) for uc in underlying_coins]

    burned_amount_underlying = swap_template.remove_liquidity_imbalance(remove_amounts_underlying, max_burn_amount_underlying, True, {"from": accounts[0]})

    assert underlying_coins[0].balanceOf(accounts[0]) == initial_underlying_coin_balances[0] + remove_amounts_underlying[0]
    assert underlying_coins[1].balanceOf(accounts[0]) == initial_underlying_coin_balances[1] + remove_amounts_underlying[1]


    # Test exceeding max burn amount
    remove_amounts_large = [10**18, 10**18]
    with pytest.raises(TransactionFailed):
        swap_template.remove_liquidity_imbalance(remove_amounts_large, 1, False, {"from": accounts[0]})

def test_exchange(swap_template, coins, accounts):
    # Add initial liquidity
    amounts = [10**18, 10**18]
    swap_template.add_liquidity(amounts, 0, False, {"from": accounts[0]})

    dx = 10**17  # 0.1 token
    min_dy = 0

    # Approve swap contract to spend tokens for the exchanger
    coins[0].approve(swap_template.address, MAX_UINT256, {"from": accounts[1]})

    initial_coin_balances = [c.balanceOf(accounts[1]) for c in coins]
    initial_swap_balances = [c.balanceOf(swap_template.address) for c in coins]

    dy = swap_template.exchange(0, 1, dx, min_dy, {"from": accounts[1]})

    assert coins[0].balanceOf(accounts[1]) == initial_coin_balances[0] - dx
    assert coins[1].balanceOf(accounts[1]) == initial_coin_balances[1] + dy
    assert coins[0].balanceOf(swap_template.address) == initial_swap_balances[0] + dx
    assert coins[1].balanceOf(swap_template.address) == initial_swap_balances[1] - dy

    # Test minimum dy requirement
    with pytest.raises(TransactionFailed):
        swap_template.exchange(0, 1, dx, dy + 100, {"from": accounts[1]})

def test_exchange_underlying(swap_template, underlying_coins, accounts, LendingPool):
    # Add initial liquidity as underlying
    amounts = [10**18, 10**18]
    swap_template.add_liquidity(amounts, 0, True, {"from": accounts[0]})

    dx = 10**17
    min_dy = 0

    # Approve swap contract to spend underlying tokens for the exchanger
    underlying_coins[0].approve(swap_template.address, MAX_UINT256, {"from": accounts[1]})

    initial_underlying_coin_balances = [uc.balanceOf(accounts[1]) for uc in underlying_coins]

    # Mock LendingPool withdraw to return the expected dy amount
    lending_pool = LendingPool(swap_template.aave_lending_pool())
    lending_pool.mock_withdraw(underlying_coins[1].address, accounts[1], lambda amount: amount) # Simplified mock

    dy = swap_template.exchange_underlying(0, 1, dx, min_dy, {"from": accounts[1]})

    assert underlying_coins[0].balanceOf(accounts[1]) == initial_underlying_coin_balances[0] - dx
    assert underlying_coins[1].balanceOf(accounts[1]) == initial_underlying_coin_balances[1] + dy # Assumes LendingPool mock transfers directly

    # Test minimum dy requirement
    with pytest.raises(TransactionFailed):
        swap_template.exchange_underlying(0, 1, dx, dy + 100, {"from": accounts[1]})


def test_ramp_A(swap_template, accounts, chain):
    owner = accounts[0]
    initial_A = swap_template.initial_A()
    future_A = initial_A * 2
    future_time = chain.time() + 2 * 86400  # MIN_RAMP_TIME

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.ramp_A(future_A // 100, future_time, {"from": accounts[1]})

    # Test insufficient time
    with pytest.raises(TransactionFailed):
        swap_template.ramp_A(future_A // 100, chain.time() + 10, {"from": owner})

    # Test future A bounds
    with pytest.raises(TransactionFailed):
        swap_template.ramp_A(MAX_A + 1, future_time, {"from": owner})
    with pytest.raises(TransactionFailed):
        swap_template.ramp_A(0, future_time, {"from": owner})
    with pytest.raises(TransactionFailed):
        swap_template.ramp_A(initial_A * (MAX_A_CHANGE + 1) // 100, future_time, {"from": owner})
    with pytest.raises(TransactionFailed):
        swap_template.ramp_A(initial_A // (MAX_A_CHANGE + 1) // 100, future_time, {"from": owner})


    swap_template.ramp_A(future_A // 100, future_time, {"from": owner})

    assert swap_template.initial_A() == initial_A
    assert swap_template.future_A() == future_A
    assert swap_template.initial_A_time() == chain.time()
    assert swap_template.future_A_time() == future_time

def test_stop_ramp_A(swap_template, accounts, chain):
    owner = accounts[0]
    future_A = swap_template.initial_A() * 2
    future_time = chain.time() + 2 * 86400
    swap_template.ramp_A(future_A // 100, future_time, {"from": owner})

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.stop_ramp_A({"from": accounts[1]})

    swap_template.stop_ramp_A({"from": owner})

    current_A = swap_template._A()
    assert swap_template.initial_A() == current_A
    assert swap_template.future_A() == current_A
    assert swap_template.initial_A_time() == chain.time()
    assert swap_template.future_A_time() == chain.time()

def test_commit_new_fee(swap_template, accounts, chain):
    owner = accounts[0]
    new_fee = FEE // 2
    new_admin_fee = ADMIN_FEE // 2
    new_offpeg_fee_multiplier = OFFPEG_FEE_MULTIPLIER // 2

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.commit_new_fee(new_fee, new_admin_fee, new_offpeg_fee_multiplier, {"from": accounts[1]})

    # Test fee bounds
    with pytest.raises(TransactionFailed):
        swap_template.commit_new_fee(MAX_FEE + 1, new_admin_fee, new_offpeg_fee_multiplier, {"from": owner})
    with pytest.raises(TransactionFailed):
        swap_template.commit_new_fee(new_fee, MAX_ADMIN_FEE + 1, new_offpeg_fee_multiplier, {"from": owner})
    with pytest.raises(TransactionFailed):
        swap_template.commit_new_fee(MAX_FEE, new_admin_fee, FEE_DENOMINATOR + 1, {"from": owner})


    swap_template.commit_new_fee(new_fee, new_admin_fee, new_offpeg_fee_multiplier, {"from": owner})

    assert swap_template.admin_actions_deadline() > 0
    assert swap_template.future_fee() == new_fee
    assert swap_template.future_admin_fee() == new_admin_fee
    assert swap_template.future_offpeg_fee_multiplier() == new_offpeg_fee_multiplier

def test_apply_new_fee(swap_template, accounts, chain):
    owner = accounts[0]
    new_fee = FEE // 2
    new_admin_fee = ADMIN_FEE // 2
    new_offpeg_fee_multiplier = OFFPEG_FEE_MULTIPLIER // 2
    swap_template.commit_new_fee(new_fee, new_admin_fee, new_offpeg_fee_multiplier, {"from": owner})

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.apply_new_fee({"from": accounts[1]})

    # Test insufficient time
    with pytest.raises(TransactionFailed):
        swap_template.apply_new_fee({"from": owner})

    chain.sleep(swap_template.admin_actions_deadline() - chain.time())
    chain.mine()

    swap_template.apply_new_fee({"from": owner})

    assert swap_template.admin_actions_deadline() == 0
    assert swap_template.fee() == new_fee
    assert swap_template.admin_fee() == new_admin_fee
    assert swap_template.offpeg_fee_multiplier() == new_offpeg_fee_multiplier

def test_revert_new_parameters(swap_template, accounts, chain):
    owner = accounts[0]
    new_fee = FEE // 2
    new_admin_fee = ADMIN_FEE // 2
    new_offpeg_fee_multiplier = OFFPEG_FEE_MULTIPLIER // 2
    swap_template.commit_new_fee(new_fee, new_admin_fee, new_offpeg_fee_multiplier, {"from": owner})

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.revert_new_parameters({"from": accounts[1]})

    swap_template.revert_new_parameters({"from": owner})

    assert swap_template.admin_actions_deadline() == 0

def test_commit_transfer_ownership(swap_template, accounts, chain):
    owner = accounts[0]
    new_owner = accounts[1]

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.commit_transfer_ownership(new_owner, {"from": accounts[1]})

    swap_template.commit_transfer_ownership(new_owner, {"from": owner})

    assert swap_template.transfer_ownership_deadline() > 0
    assert swap_template.future_owner() == new_owner

def test_apply_transfer_ownership(swap_template, accounts, chain):
    owner = accounts[0]
    new_owner = accounts[1]
    swap_template.commit_transfer_ownership(new_owner, {"from": owner})

    # Test only current owner can call (even though transferring)
    with pytest.raises(TransactionFailed):
        swap_template.apply_transfer_ownership({"from": new_owner})

    # Test insufficient time
    with pytest.raises(TransactionFailed):
        swap_template.apply_transfer_ownership({"from": owner})

    chain.sleep(swap_template.transfer_ownership_deadline() - chain.time())
    chain.mine()

    swap_template.apply_transfer_ownership({"from": owner})

    assert swap_template.transfer_ownership_deadline() == 0
    assert swap_template.owner() == new_owner

def test_revert_transfer_ownership(swap_template, accounts, chain):
    owner = accounts[0]
    new_owner = accounts[1]
    swap_template.commit_transfer_ownership(new_owner, {"from": owner})

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.revert_transfer_ownership({"from": accounts[1]})

    swap_template.revert_transfer_ownership({"from": owner})

    assert swap_template.transfer_ownership_deadline() == 0

def test_withdraw_admin_fees(swap_template, coins, accounts):
    owner = accounts[0]
    # Simulate some admin fees accrued
    swap_template.admin_balances = [100, 200]

    initial_owner_coin_balances = [c.balanceOf(owner) for c in coins]

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.withdraw_admin_fees({"from": accounts[1]})

    swap_template.withdraw_admin_fees({"from": owner})

    for i in range(N_COINS):
        assert swap_template.admin_balances[i] == 0
        assert coins[i].balanceOf(owner) == initial_owner_coin_balances[i] + [100, 200][i]

def test_donate_admin_fees(swap_template, accounts):
    owner = accounts[0]
    # Simulate some admin fees accrued
    swap_template.admin_balances = [100, 200]

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.donate_admin_fees({"from": accounts[1]})

    swap_template.donate_admin_fees({"from": owner})

    for i in range(N_COINS):
        assert swap_template.admin_balances[i] == 0

def test_kill_me(swap_template, accounts, chain):
    owner = accounts[0]

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.kill_me({"from": accounts[1]})

    # Test deadline not passed
    with pytest.raises(TransactionFailed):
        swap_template.kill_me({"from": owner})

    chain.sleep(swap_template.kill_deadline() - chain.time())
    chain.mine()

    swap_template.kill_me({"from": owner})
    assert swap_template.is_killed() == True

def test_unkill_me(swap_template, accounts, chain):
    owner = accounts[0]
    chain.sleep(swap_template.kill_deadline() - chain.time())
    chain.mine()
    swap_template.kill_me({"from": owner})

    # Test only owner can call
    with pytest.raises(TransactionFailed):
        swap_template.unkill_me({"from": accounts[1]})

    swap_template.unkill_me({"from": owner})
    assert swap_template.is_killed() == False

# Mock LendingPool contract for testing purposes
@pytest.fixture
def LendingPool(vyper_module, accounts):
    lending_pool_code = """
# @version ^0.2.8

events: map(address, map(address, uint256)) # receiver -> asset -> amount

@external
def withdraw(_underlying_asset: address, _amount: uint256, _receiver: address):
    self.events[_receiver][_underlying_asset] = _amount

@internal
def mock_withdraw(_underlying_asset: address, _receiver: address, _amount: uint256):
    self.withdraw(_underlying_asset, _amount, _receiver)

"""
    return vyper_module(lending_pool_code)

# Mock CurveToken contract for testing purposes
@pytest.fixture
def CurveToken(vyper_module, accounts):
    curve_token_code = """
# @version ^0.2.8

name: public(String[32])
symbol: public(String[10])
decimals: public(uint8)
balanceOf: public(map[address, uint256])
totalSupply: public(uint256)
allowance: public(map[address, map[address, uint256]])

@external
def __init__(_name: String[32], _symbol: String[10], _decimals: uint8):
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals

@internal
def mint(_to: address, _value: uint256) -> bool:
    self.balanceOf[_to] += _value
    self.totalSupply += _value
    return True

@internal
def burnFrom(_to: address, _value: uint256) -> bool:
    self.balanceOf[_to] -= _value
    self.totalSupply -= _value
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    self.allowance[msg.sender][_spender] = _value
    return True

"""
    return vyper_module(curve_token_code)


# Mock ERC20 contract for testing purposes
@pytest.fixture
def ERC20(vyper_module, accounts):
    erc20_code = """
# @version ^0.2.8

name: public(String[32])
symbol: public(String[10])
decimals: public(uint8)
balanceOf: public(map[address, uint256])
totalSupply: public(uint256)
allowance: public(map[address, map[address, uint256]])

@external
def __init__(_name: String[32], _symbol: String[10], _decimals: uint8, _supply: uint256):
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals
    self.balanceOf[msg.sender] = _supply
    self.totalSupply = _supply

@external
def transfer(_to: address, _value: uint256) -> bool:
    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    self.allowance[_from][msg.sender] -= _value
    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    self.allowance[msg.sender][_spender] = _value
    return True
"""
    return vyper_module(erc20_code)


# Load the contract code
@pytest.fixture
def SwapTemplateA(vyper_module):
    with open("./curve-contract/contracts/pools/ethx/SwapTemplateA.vy") as f:
        return vyper_module(f.read())