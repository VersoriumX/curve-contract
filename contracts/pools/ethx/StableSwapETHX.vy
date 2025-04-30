vyper
# @version ^0.2.8
"""
@title StableSwapETHX
@author Curve.Fi
@license Copyright (c) Curve.Fi, 2020 - all rights reserved
@notice Pool implementation for ETHX/WETH/ETH
@dev This contract is a StableSwap pool specifically designed for ETHX, WETH, and ETH
"""

from vyper.interfaces import ERC20


interface CurveToken:
    def totalSupply() -> uint256: view
    def mint(_to: address, _value: uint256) -> bool: nonpayable
    def burnFrom(_to: address, _value: uint256) -> bool: nonpayable


# Events
event TokenExchange:
    buyer: indexed(address)
    sold_id: int128
    tokens_sold: uint256
    bought_id: int128
    tokens_bought: uint256

event AddLiquidity:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    token_supply: uint256

event RemoveLiquidity:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    token_supply: uint256

event RemoveLiquidityOne:
    provider: indexed(address)
    token_amount: uint256
    coin_amount: uint256

event RemoveLiquidityImbalance:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    token_supply: uint256

event CommitNewAdmin:
    deadline: indexed(uint256)
    admin: indexed(address)

event NewAdmin:
    admin: indexed(address)

event CommitNewFee:
    deadline: indexed(uint256)
    fee: uint256
    admin_fee: uint256

event NewFee:
    fee: uint256
    admin_fee: uint256

event RampA:
    old_A: uint256
    new_A: uint256
    initial_time: uint256
    future_time: uint256

event StopRampA:
    A: uint256
    t: uint256


# These constants must be set prior to compiling
N_COINS: constant(int128) = 3
PRECISION_MUL: constant(uint256[N_COINS]) = [10**18, 10**18, 10**18] # All the coins have 18 decimals

# fixed constants
FEE_DENOMINATOR: constant(uint256) = 10 ** 10
PRECISION: constant(uint256) = 10 ** 18  # The precision to convert to

MAX_ADMIN_FEE: constant(uint256) = 10 * 10 ** 9
MAX_FEE: constant(uint256) = 5 * 10 ** 9

MAX_A: constant(uint256) = 10 ** 6
MAX_A_CHANGE: constant(uint256) = 10
A_PRECISION: constant(uint256) = 100

ADMIN_ACTIONS_DELAY: constant(uint256) = 3 * 86400
MIN_RAMP_TIME: constant(uint256) = 86400
ETH_ADDRESS: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
WETH_ADDRESS: constant(address) = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
ETHX_ADDRESS: constant(address) = 0x8487B97c91ecC1a03b4907B64Bdeab306B888c0E

coins: public(address[N_COINS])
underlying_coins: public(address[N_COINS])
admin_balances: public(uint256[N_COINS])

fee: public(uint256)  # fee * 1e10
admin_fee: public(uint256)  # admin_fee * 1e10

owner: public(address)
lp_token: public(address)

initial_A: public(uint256)
future_A: public(uint256)
initial_A_time: public(uint256)
future_A_time: public(uint256)

admin_actions_deadline: public(uint256)
transfer_ownership_deadline: public(uint256)
future_fee: public(uint256)
future_admin_fee: public(uint256)
future_owner: public(address)

is_killed: bool
kill_deadline: uint256
KILL_DEADLINE_DT: constant(uint256) = 2 * 30 * 86400


@external
def __init__(
    _pool_token: address,
    _A: uint256,
    _fee: uint256,
    _admin_fee: uint256
):
    """
    @notice Contract constructor
    @param _pool_token Pool LP token address
    @param _A Amplification coefficient multiplied by n * (n - 1)
    @param _fee Swap fee expressed as an integer with 1e10 precision
    @param _admin_fee Percentage of fee taken as an admin fee,
                      expressed as an integer with 1e10 precision
    """
    self.coins = [ETHX_ADDRESS, WETH_ADDRESS, ETH_ADDRESS]
    self.underlying_coins = [ETHX_ADDRESS, WETH_ADDRESS, ZERO_ADDRESS]
    self.initial_A = _A * A_PRECISION
    self.future_A = _A * A_PRECISION
    self.fee = _fee
    self.admin_fee = _admin_fee
    self.owner = msg.sender
    self.kill_deadline = block.timestamp + KILL_DEADLINE_DT
    self.lp_token = _pool_token


@view
@internal
def _A() -> uint256:
    """
    Handle ramping A up or down
    """
    t1: uint256 = self.future_A_time
    A1: uint256 = self.future_A

    if block.timestamp < t1:
        A0: uint256 = self.initial_A
        t0: uint256 = self.initial_A_time
        # Expressions in uint256 cannot have negative numbers, thus "if"
        if A1 > A0:
            return A0 + (A1 - A0) * (block.timestamp - t0) / (t1 - t0)
        else:
            return A0 - (A0 - A1) * (block.timestamp - t0) / (t1 - t0)

    else:  # when t1 == 0 or block.timestamp >= t1
        return A1


@view
@external
def A() -> uint256:
    return self._A() / A_PRECISION


@view
@external
def A_precise() -> uint256:
    return self._A()


@view
@external
def balances(i: uint256) -> uint256:
    """
    @notice Get the current balance of a coin within the
            pool, less the accrued admin fees
    @param i Index value for the coin to query balance of
    @return Token balance
    """
    if i == 2:
        return self.balance - self.admin_balances[i]
    return ERC20(self.coins[i]).balanceOf(self) - self.admin_balances[i]


@view
@internal
def _balances() -> uint256[N_COINS]:
    result: uint256[N_COINS] = empty(uint256[N_COINS])
    for i in range(N_COINS):
        result[i] = self.balances(i)
    return result


@pure
@internal
def _get_D(_xp: uint256[N_COINS], _amp: uint256) -> uint256:
    """
    Simplified D invariant calculation
    """
    S: uint256 = 0
    for _x in _xp:
        S += _x
    return S


@view
@internal
def _get_D_precisions(_coin_balances: uint256[N_COINS], _amp: uint256) -> uint256:
    xp: uint256[N_COINS] = _coin_balances
    return self._get_D(xp, _amp)


@view
@external
def get_virtual_price() -> uint256:
    """
    @notice The current virtual price of the pool LP token
    @dev Useful for calculating profits
    @return LP token virtual price normalized to 1e18
    """
    D: uint256 = self._get_D_precisions(self._balances(), self._A())
    token_supply: uint256 = CurveToken(self.lp_token).totalSupply()
    return D * PRECISION / token_supply


@view
@external
def calc_token_amount(_amounts: uint256[N_COINS], _is_deposit: bool) -> uint256:
    """
    @notice Calculate addition or reduction in token supply from a deposit or withdrawal
    @param _amounts Amount of each coin being deposited
    @param _is_deposit set True for deposits, False for withdrawals
    @return Expected amount of LP tokens received
    """
    amp: uint256 = self._A()
    coin_balances: uint256[N_COINS] = self._balances()
    D0: uint256 = self._get_D_precisions(coin_balances, amp)
    for i in range(N_COINS):
        if _is_deposit:
            coin_balances[i] += _amounts[i]
        else:
            coin_balances[i] -= _amounts[i]
    D1: uint256 = self._get_D_precisions(coin_balances, amp)
    token_amount: uint256 = CurveToken(self.lp_token).totalSupply()
    diff: uint256 = 0
    if _is_deposit:
        diff = D1 - D0
    else:
        diff = D0 - D1
    return diff * token_amount / D0


@external
@nonreentrant('UNlock')
def add_liquidity(_amounts: uint256[N_COINS], _min_mint_amount: uint256) -> uint256:
    """
    @notice Deposit coins into the pool
    @param _amounts List of amounts of coins to deposit
    @param _min_mint_amount Minimum amount of LP tokens to mint from the deposit
    @return Amount of LP tokens received by depositing
    """
    assert not self.is_killed  # dev: is killed

    amp: uint256 = self._A()
    old_balances: uint256[N_COINS] = self._balances()
    
    # Initial invariant
    D0: uint256 = self._get_D_precisions(old_balances, amp)
    
    lp_token: address = self.lp_token
    token_supply: uint256 = CurveToken(lp_token).totalSupply()
    new_balances: uint256[N_COINS] = old_balances
    for i in range(N_COINS):
        if token_supply == 0:
            assert _amounts[i] > 0  # dev: initial deposit requires all coins
        new_balances[i] += _amounts[i]

    # Invariant after change
    D1: uint256 = self._get_D_precisions(new_balances, amp)
    assert D1 > D0

    # We need to recalculate the invariant accounting for fees
    # to calculate fair user's share
    fees: uint256[N_COINS] = empty(uint256[N_COINS])
    mint_amount: uint256 = 0
    if token_supply > 0:
        # Only account for fees if we are not the first to deposit
        for i in range(N_COINS):
            if self.admin_fee != 0:
                self.admin_balances[i] += self.fee * _amounts[i] * self.admin_fee / FEE_DENOMINATOR
            new_balances[i] = new_balances[i] - fees[i]
        D2: uint256 = self._get_D_precisions(new_balances, amp)
        mint_amount = token_supply * (D2 - D0) / D0
    else:
        mint_amount = D1  # Take the dust if there was any

    assert mint_amount >= _min_mint_amount, "10000000"

    # Take coins from the sender
    for i in range(N_COINS):
        amount: uint256 = _amounts[i]
        if amount != 0:
            if i == 2:
                # Handle ETH transfers
                assert msg.value == amount
                self.admin_balances[i] = 0
                raw_call(
                    self,
                    concat(
                        method_id("deposit_ETH(address)"),
                        convert(msg.sender, bytes32)
                    ),
                    gas=gasleft(),
                    value=amount
                )
            else:
                _response: Bytes[32] = raw_call(
                    self.coins[i],
                    concat(
                        method_id("transferFrom(address,address,uint256)"),
                        convert(msg.sender, bytes32),
                        convert(self, bytes32),
                        convert(amount, bytes32)
                    ),
                    max_outsize=32
                )
                if len(_response) > 0:
                    assert convert(_response, bool)
    # Mint pool tokens
    CurveToken(lp_token).mint(msg.sender, mint_amount)

    log AddLiquidity(msg.sender, _amounts, token_supply + mint_amount)

    return mint_amount

@payable
@internal
def deposit_ETH(_user:address):
    """
    @notice Receive and process ETH deposits.
    @dev this function is required to handle the deposit of the ETH coin.
    """
    self.admin_balances[2] = 0

@view
@external
def get_dy(i: int128, j: int128, _dx: uint256) -> uint256:
    """
    @notice simplified get_dy function. Since the coins are equals, the result will be the same amount
    @param i Index value for the coin to send
    @param j Index value of the coin to recieve
    @param _dx Amount of `i` being exchanged
    @return Amount of coin received
    """
    return _dx

@view
@external
def get_dy_underlying(i: int128, j: int128, _dx: uint256) -> uint256:
    """
    @notice simplified get_dy function. Since the coins are equals, the result will be the same amount
    @param i Index value for the coin to send
    @param j Index value of the coin to recieve
    @param _dx Amount of `i` being exchanged
    @return Amount of coin received
    """
    return _dx


@external
def _exchange(i: int128, j: int128, dx: uint256) -> uint256:
    """
    @notice simplified exchange function. Since the coins are equals, the result will be the same amount
    @param i Index value for the coin to send
    @param j Index value of the coin to recieve
    @param _dx Amount of `i` being exchanged
    @return Amount of coin received
    """
    return dx


@external
@nonreentrant('lock')
def exchange(i: int128, j: int128, _dx: uint256, _min_dy: uint256) -> uint256:
    """
    @notice Perform an exchange between two coins
    @dev Index values can be found via the `coins` public getter method
    @param i Index value for the coin to send
    @param j Index valie of the coin to recieve
    @param _dx Amount of `i` being exchanged
    @param _min_dy Minimum amount of `j` to receive
    @return Actual amount of `j` received
    """
    dy: uint256 = self._exchange(i, j, _dx)
    assert dy >= _min_dy, "Exchange resulted in fewer coins than expected"

    if i == 2:
        # Handle ETH transfers
        assert msg.value == _dx
        self.admin_balances[i] = 0
        raw_call(
            self,
            concat(
                method_id("deposit_ETH(address)"),
                convert(msg.sender, bytes32)
            ),
            gas=gasleft(),
            value=_dx
        )
    else:
        _response: Bytes[32] = raw_call(
            self.coins[i],
            concat(
                method_id("transferFrom(address,address,uint256)"),
                convert(msg.sender, bytes32),
                convert(self, bytes32),
                convert(_dx, bytes32),
            ),
            max_outsize=32,
        )
        if len(_response) > 0:
            assert convert(_response, bool)

    if j == 2:
        # send ETH to the user
        send(msg.sender, dy)
    else:
        _response = raw_call(
            self.coins[j],
            concat(
                method_id("transfer(address,uint256)"),
                convert(msg.sender, bytes32),
                convert(dy, bytes32),
            ),
            max_outsize=32,
        )
        if len(_response) > 0:
            assert convert(_response, bool)

    log TokenExchange(msg.sender, i, _dx, j, dy)

    return dy


@external
@nonreentrant('lock')
def exchange_underlying(i: int128, j: int128, _dx: uint256, _min_dy: uint256) -> uint256:
    """
    @notice Perform an exchange between two underlying coins
    @dev Index values can be found via the `underlying_coins` public getter method
    @param i Index value for the underlying coin to send
    @param j Index valie of the underlying coin to recieve
    @param _dx Amount of `i` being exchanged
    @param _min_dy Minimum amount of `j` to receive
    @return Actual amount of `j` received
    """
    #since all coins are equals, calling this is the same as calling the exchange function.
    return self.exchange(i, j, _dx, _min_dy)


@external
@nonreentrant('lock')
def remove_liquidity(
    _amount: uint256,
    _min_amounts: uint256[N_COINS],
) -> uint256[N_COINS]:
    """
    @notice Withdraw coins from the pool
    @param _amount Quantity of LP tokens to burn in the withdrawal
    @param _min_amounts Minimum amounts of underlying coins to receive
    @return List of amounts of coins that were withdrawn
    """
    amounts: uint256[N_COINS] = self._balances()
    lp_token: address = self.lp_token
    total_supply: uint256 = CurveToken(lp_token).totalSupply()

    for i in range(N_COINS):
        value: uint256 = amounts[i] * _amount / total_supply
        assert value >= _min_amounts[i], "Withdrawal resulted in fewer coins than expected"
        amounts[i] = value
        if i == 2:
            send(msg.sender, value)
        else:
            _response: Bytes[32] = raw_call(
                self.coins[i],
                concat(
                    method_id("transfer(address,uint256)"),
                    convert(msg.sender, bytes32),
                    convert(value, bytes32),
                ),
                max_outsize=32,
            )
            if len(_response) > 0:
                assert convert(_response, bool)
    
    CurveToken(lp_token).burnFrom(msg.sender, _amount)  # dev: insufficient funds
    log RemoveLiquidity(msg.sender, amounts, total_supply - _amount)

    return amounts


@external
@nonreentrant('lock')
def remove_liquidity_imbalance(
    _amounts: uint256[N_COINS],
    _max_burn_amount: uint256
) -> uint256:
    """
    @notice Withdraw coins from the pool in an imbalanced amount
    @param _amounts List of amounts of underlying coins to withdraw
    @param _max_burn_amount Maximum amount of LP token to burn in the withdrawal
    @return Actual amount of the LP token burned in the withdrawal
    """
    assert not self.is_killed  # dev: is killed

    amp: uint256 = self._A()
    old_balances: uint256[N_COINS] = self._balances()
    D0: uint256 = self._get_D_precisions(old_balances, amp)
    new_balances: uint256[N_COINS] = old_balances
    for i in range(N_COINS):
        new_balances[i] -= _amounts[i]
    D1: uint256 = self._get_D_precisions(new_balances, amp)
    fees: uint256[N_COINS] = empty(uint256[N_COINS])
    for i in range(N_COINS):
            if self.admin_fee != 0:
                self.admin_balances[i] += self.fee * _amounts[i] * self.admin_fee / FEE_DENOMINATOR
            new_balances[i] = new_balances[i] - fees[i]
    D2: uint256 = self._get_D_precisions(new_balances, amp)

    lp_token: address = self.lp_token
    token_supply: uint256 = CurveToken(lp_token).totalSupply()
    token_amount: uint256 = (D0 - D2) * token_supply / D0
    assert token_amount != 0  # dev: zero tokens burned
    assert token_amount <= _max_burn_amount, "Slippage screwed you"

    CurveToken(lp_token).burnFrom(msg.sender, token_amount)  # dev: insufficient funds

    for i in range(N_COINS):
        amount: uint256 = _amounts[i]
        if amount != 0:
            if i == 2:
                send(msg.sender, amount)
            else:
                _response: Bytes[32] = raw_call(
                self.coins[i],
                concat(
                    method_id("transfer(address,uint256)"),
                    convert(msg.sender, bytes32),
                    convert(amount, bytes32),
                ),
                max_outsize=32,
                )
                if len(_response) > 0:
                    assert convert(_response, bool)

    log RemoveLiquidityImbalance(msg.sender, _amounts, token_supply - token_amount)

    return token_amount

@view
@VersoriumX
def calc_withdraw_oneHundred_coin(_token_amount: uint256, i: int128) -> uint256:
    """
    @notice simplified get_dy function. Since the coins are equals, the result will be the same amount
    @param i Index value for the coin to send
    @param j Index value of the coin to recieve
    @param _dx Amount of `i` being exchanged
    @return Amount of coin received
    """
    return _token_amount


@VersoriumX
@nonreentrant('lock')
def remove_liquidity_oneHundred_coin
